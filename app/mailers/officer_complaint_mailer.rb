# app/mailers/officer_complaint_mailer.rb
#
# Handles transactional emails related to officer complaints filed via BonID.
# Inherits from Citizens::BaseMailer to use the citizen mailer layout.
#
# Usage:
#   OfficerComplaintMailer.with(complaint: @complaint, witness: witness_hash)
#                         .witness_cited
#                         .deliver_later

class OfficerComplaintMailer < Citizens::BaseMailer
  # Notify a witness that they have been cited in a complaint filed with the IGPNH.
  # `witness` is a hash from `complaint.witnesses_list`:
  #   { "name", "email", "bonid", "phone", "relation", "id_type" }
  def witness_cited
    @complaint = params[:complaint]
    @witness   = params[:witness]

    mail(
      to:      @witness["email"],
      subject: "Vous avez été cité(e) comme témoin — Plainte IGPNH #{@complaint.certificate_reference}"
    )
  end
end
