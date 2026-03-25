# app/controllers/emergency_contacts_controller.rb
class EmergencyContactsController < Citizens::BaseController
  before_action :authenticate_citizen!

  # GET /emergency_contacts/fetch_from_bonid?bonid=BONID: MO-1968-M-OUEST-P-6790
  def fetch_from_bonid
    raw_bonid = params[:bonid].to_s.strip

    # ✅ Normalize BonID (remove prefix, spaces, dashes, lowercase, etc.)
    bonid = normalize_bonid(raw_bonid)

    if bonid.blank?
      return render json: { success: false, error: "BonID is required." }, status: :bad_request
    end

    # 🚫 Prevent citizen from adding their own BonID
    if bonid == normalize_bonid(current_citizen.bonid)
      return render json: { success: false, error: "You cannot add yourself as an emergency contact." }, status: :forbidden
    end

    # ✅ Lookup verified user by normalized BonID (full match or suffix match)
    submission = IdentitySubmission
                   .approved
                   .where("REPLACE(UPPER(bonid), '-', '') = ?", bonid)
                   .order(verified_at: :desc)
                   .includes(:user)
                   .first

    # Suffix match: if full match fails, try last 6 chars (family form sends just the suffix)
    if submission.nil? && bonid.length >= 6 && bonid.length <= 8
      submission = IdentitySubmission
                     .approved
                     .where("REPLACE(UPPER(bonid), '-', '') LIKE ?", "%#{bonid}")
                     .order(verified_at: :desc)
                     .includes(:user)
                     .first
    end

    if submission&.user
      user = submission.user

      # Block self-reference (check both user table bonid and submission bonid)
      if user.id == current_citizen.id
        return render json: { success: false, error: "Ou pa ka ajoute tèt ou kòm fanmi." }, status: :forbidden
      end

      # Use first + last name only (no prefix/suffix like Mr/Mrs)
      simple_name = [user.first_name, user.last_name].compact_blank.map(&:titleize).join(" ")

      render json: {
        success: true,
        bonid: user.bonid,
        name: simple_name,
        sex: user.sex,
        phone: user.phone,
        email: user.email,
        address: user.address&.formatted_address,
        photo_url: user.photo.attached? ? Rails.application.routes.url_helpers.rails_blob_url(user.photo, only_path: true) : nil
      }
    else
      render json: { success: false, error: "No verified user found for this BonID." }, status: :not_found
    end

  rescue => e
    Rails.logger.error("[EmergencyContactsController] BonID fetch failed: #{e.class} — #{e.message}")
    render json: { success: false, error: "Server error. Please retry later." }, status: :internal_server_error
  end

  private

  # === BonID Normalizer ===
  def normalize_bonid(bonid)
    bonid.to_s
         .strip
         .gsub(/^BONID:\s*/i, "") # removes any prefix like "BONID:" or "BonID:"
         .upcase
         .gsub(/[^A-Z0-9]/, "")   # strips dashes, spaces, and other symbols
  end
end
