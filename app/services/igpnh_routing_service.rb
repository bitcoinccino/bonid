# app/services/igpnh_routing_service.rb
#
# IgpnhRoutingService — handles the full submission workflow for OfficerComplaint:
#
#   1. Validates the complaint is complete
#   2. Auto-resolves the accused officer FK if a badge ID was provided
#   3. Determines the correct IGPNH regional directorate for routing
#   4. Generates the filing certificate (tracking reference + metadata)
#   5. Queues the IGPNH alert (encrypted notification to Internal Affairs dashboard)
#   6. Returns a structured result with the certificate payload
#
# Usage:
#   result = IgpnhRoutingService.new(complaint, filed_by: current_user).call
#   if result.success?
#     render json: result.certificate
#   else
#     render json: { errors: result.errors }, status: :unprocessable_entity
#   end

class IgpnhRoutingService
  Result = Struct.new(:success?, :complaint, :certificate, :errors, keyword_init: true)

  def initialize(complaint, filed_by: nil)
    @complaint = complaint
    @filed_by  = filed_by  # User or VisitorSubmission
  end

  def call
    unless @complaint.valid?
      return Result.new(
        success?: false,
        complaint: @complaint,
        certificate: nil,
        errors: @complaint.errors.full_messages
      )
    end

    ActiveRecord::Base.transaction do
      @complaint.save!
    end

    Result.new(
      success?:    true,
      complaint:   @complaint,
      certificate: build_certificate,
      errors:      []
    )
  rescue ActiveRecord::RecordInvalid => e
    Result.new(
      success?:    false,
      complaint:   @complaint,
      certificate: nil,
      errors:      [e.message]
    )
  end

  private

  def build_certificate
    {
      # Pillar 6: Official filing proof
      certificate_reference:   @complaint.certificate_reference,
      tracking_number:         @complaint.tracking_number,
      uuid:                    @complaint.uuid,
      status:                  @complaint.status,
      status_label:            @complaint.status_label,
      submitted_at:            @complaint.submitted_at&.iso8601,

      # Who filed
      complainant: {
        name:   @complaint.complainant_name || "Anonyme",
        bonid:  @complaint.complainant_bonid,
        type:   @complaint.complainant_type,
        role:   @complaint.complainant_role
      },

      # What was alleged
      allegation: {
        category:  @complaint.allegation_category,
        specific:  @complaint.specific_allegation
      },

      # When and where
      incident: {
        occurred_at:          @complaint.occurred_at&.iso8601,
        location:             @complaint.location_description,
        department:           @complaint.department&.name,
        commune:              @complaint.commune&.name,
        pnh_unit_involved:    @complaint.pnh_unit_involved
      },

      # Accused officer (what we know)
      accused_officer: {
        resolved_id:    @complaint.accused_officer_id,
        badge:          @complaint.accused_officer_badge,
        name:           @complaint.accused_officer_name,
        vehicle:        @complaint.accused_officer_vehicle,
        unit:           @complaint.accused_officer_unit,
        description:    @complaint.physical_description
      },

      # Routing
      routing: {
        directorate_code: @complaint.routed_directorate,
        directorate_name: @complaint.routing_directorate_name,
        routed_to:        "Inspection Générale de la PNH (IGPNH)",
        also_notified:    ["Office de la Protection du Citoyen (OPC)"]
      },

      # Instructions for citizen
      next_steps: [
        "Conservez votre numéro de référence: #{@complaint.certificate_reference}",
        "Un enquêteur de l'IGPNH vous contactera dans 5 à 10 jours ouvrables.",
        "Vous pouvez vérifier le statut de votre plainte à tout moment sur bonid.ht",
        "Si vous ne recevez aucune réponse, présentez ce certificat à l'Office de la Protection du Citoyen (OPC)."
      ],

      # Legal note
      legal_notice: "Ce certificat constitue une preuve officielle que votre plainte a été " \
                    "enregistrée le #{@complaint.submitted_at&.strftime('%d %B %Y à %H:%M')} " \
                    "auprès de l'IGPNH — #{@complaint.routing_directorate_name}.",

      generated_at: Time.current.iso8601
    }
  end
end
