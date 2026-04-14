# frozen_string_literal: true

require "rails_helper"

RSpec.describe FaceCollectionService do
  let(:selfie_bytes) { "fake-selfie-bytes" }
  let(:current_user_id) { 42 }
  let(:other_user_id) { 99 }
  let(:fake_face_id) { "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee" }
  let(:rekognition_client) { instance_double(Aws::Rekognition::Client) }

  before do
    allow(FaceMatchService).to receive(:rekognition_client).and_return(rekognition_client)
  end

  # ─────────────────────────────────────────────────────────
  # .search
  # ─────────────────────────────────────────────────────────
  describe ".search" do
    before do
      # Collection exists by default
      allow(rekognition_client).to receive(:describe_collection).and_return(
        double(face_count: 10, creation_timestamp: Time.current, face_model_version: "7.0")
      )
    end

    context "when no faces match (clean)" do
      before do
        allow(rekognition_client).to receive(:search_faces_by_image).and_return(
          double(face_matches: [])
        )
      end

      it "returns duplicate: false" do
        result = described_class.search(selfie_bytes, current_user_id)
        expect(result).to eq({ duplicate: false })
      end
    end

    context "when a match is found for a DIFFERENT user (fraud)" do
      before do
        match = double(
          face: double(
            external_image_id: other_user_id.to_s,
            face_id: fake_face_id
          ),
          similarity: 95.72
        )
        allow(rekognition_client).to receive(:search_faces_by_image).and_return(
          double(face_matches: [match])
        )
      end

      it "returns duplicate: true with matched user info" do
        result = described_class.search(selfie_bytes, current_user_id)

        expect(result[:duplicate]).to be true
        expect(result[:matched_user_id]).to eq(other_user_id)
        expect(result[:matched_face_id]).to eq(fake_face_id)
        expect(result[:similarity]).to eq(95.72)
      end
    end

    context "when match belongs to the SAME user (legitimate reissue)" do
      before do
        match = double(
          face: double(
            external_image_id: current_user_id.to_s,
            face_id: fake_face_id
          ),
          similarity: 98.5
        )
        allow(rekognition_client).to receive(:search_faces_by_image).and_return(
          double(face_matches: [match])
        )
      end

      it "returns duplicate: false with same_user: true" do
        result = described_class.search(selfie_bytes, current_user_id)

        expect(result[:duplicate]).to be false
        expect(result[:same_user]).to be true
      end
    end

    context "when no face is detected in the selfie" do
      before do
        allow(rekognition_client).to receive(:search_faces_by_image).and_raise(
          Aws::Rekognition::Errors::InvalidParameterException.new(nil, "No face detected in the image")
        )
      end

      it "returns duplicate: false with no_face: true" do
        result = described_class.search(selfie_bytes, current_user_id)

        expect(result[:duplicate]).to be false
        expect(result[:no_face]).to be true
      end
    end

    context "when AWS returns a service error" do
      before do
        allow(rekognition_client).to receive(:search_faces_by_image).and_raise(
          Aws::Rekognition::Errors::ServiceError.new(nil, "Internal server error")
        )
      end

      it "returns an error hash (non-blocking)" do
        result = described_class.search(selfie_bytes, current_user_id)
        expect(result[:error]).to be_present
      end
    end

    context "when collection does not exist" do
      before do
        allow(rekognition_client).to receive(:describe_collection).and_raise(
          Aws::Rekognition::Errors::ResourceNotFoundException.new(nil, "Collection not found")
        )
      end

      it "returns duplicate: false without calling search" do
        expect(rekognition_client).not_to receive(:search_faces_by_image)
        result = described_class.search(selfie_bytes, current_user_id)
        expect(result).to eq({ duplicate: false })
      end
    end
  end

  # ─────────────────────────────────────────────────────────
  # .index
  # ─────────────────────────────────────────────────────────
  describe ".index" do
    before do
      # ensure_collection! succeeds
      allow(rekognition_client).to receive(:describe_collection).and_return(
        double(face_count: 10, creation_timestamp: Time.current, face_model_version: "7.0")
      )
    end

    context "when face is successfully indexed" do
      before do
        face_record = double(face: double(face_id: fake_face_id))
        allow(rekognition_client).to receive(:index_faces).and_return(
          double(face_records: [face_record])
        )
      end

      it "returns the face_id" do
        result = described_class.index(selfie_bytes, current_user_id)
        expect(result).to eq(fake_face_id)
      end

      it "calls index_faces with correct params" do
        expect(rekognition_client).to receive(:index_faces).with(
          collection_id: "bonid-verified-faces",
          image: { bytes: selfie_bytes },
          external_image_id: current_user_id.to_s,
          max_faces: 1,
          detection_attributes: ["DEFAULT"],
          quality_filter: "AUTO"
        )
        described_class.index(selfie_bytes, current_user_id)
      end
    end

    context "when quality filter rejects the face" do
      before do
        allow(rekognition_client).to receive(:index_faces).and_return(
          double(face_records: [])
        )
      end

      it "returns nil" do
        result = described_class.index(selfie_bytes, current_user_id)
        expect(result).to be_nil
      end
    end

    context "when AWS returns a service error" do
      before do
        allow(rekognition_client).to receive(:index_faces).and_raise(
          Aws::Rekognition::Errors::ServiceError.new(nil, "Throttled")
        )
      end

      it "returns nil (non-blocking)" do
        result = described_class.index(selfie_bytes, current_user_id)
        expect(result).to be_nil
      end
    end
  end

  # ─────────────────────────────────────────────────────────
  # .remove
  # ─────────────────────────────────────────────────────────
  describe ".remove" do
    context "with a valid face_id" do
      before do
        allow(rekognition_client).to receive(:delete_faces).and_return(double)
      end

      it "returns true" do
        expect(described_class.remove(fake_face_id)).to be true
      end

      it "calls delete_faces with correct params" do
        expect(rekognition_client).to receive(:delete_faces).with(
          collection_id: "bonid-verified-faces",
          face_ids: [fake_face_id]
        )
        described_class.remove(fake_face_id)
      end
    end

    context "with nil face_id" do
      it "returns nil without calling AWS" do
        expect(rekognition_client).not_to receive(:delete_faces)
        expect(described_class.remove(nil)).to be_nil
      end
    end

    context "when AWS returns a service error" do
      before do
        allow(rekognition_client).to receive(:delete_faces).and_raise(
          Aws::Rekognition::Errors::ServiceError.new(nil, "Not found")
        )
      end

      it "returns false (non-blocking)" do
        expect(described_class.remove(fake_face_id)).to be false
      end
    end
  end

  # ─────────────────────────────────────────────────────────
  # .collection_stats
  # ─────────────────────────────────────────────────────────
  describe ".collection_stats" do
    context "when collection exists" do
      let(:timestamp) { Time.current }

      before do
        allow(rekognition_client).to receive(:describe_collection).and_return(
          double(face_count: 150, creation_timestamp: timestamp, face_model_version: "7.0")
        )
      end

      it "returns stats hash" do
        stats = described_class.collection_stats
        expect(stats[:face_count]).to eq(150)
        expect(stats[:model_version]).to eq("7.0")
      end
    end

    context "when collection does not exist" do
      before do
        allow(rekognition_client).to receive(:describe_collection).and_raise(
          Aws::Rekognition::Errors::ResourceNotFoundException.new(nil, "Not found")
        )
      end

      it "returns zero counts" do
        stats = described_class.collection_stats
        expect(stats[:face_count]).to eq(0)
        expect(stats[:exists]).to be false
      end
    end
  end
end
