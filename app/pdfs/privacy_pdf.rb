# app/pdfs/privacy_pdf.rb
class PrivacyPdf < Prawn::Document
  def initialize
    super(margin: 50)
    stroke_color '6C757D' # Mid Gray for bounds
    stroke_bounds

    font "Helvetica"

    # Header
    header
    move_down 80 # Move below 60px header + padding

    # Main title
    text "BonID Privacy Policy", size: 28, style: :bold, align: :center, color: '3366CC' # Ocean Blue
    move_down 25

    # Subtitle
    text "Your privacy is our priority. Learn how we protect your data.", align: :center, size: 12, color: '343A40' # Dark Gray
    move_down 35

    # Content sections
    section_title "1. Information We Collect"
    body_text "We collect only the data necessary for identity verification and service provision."
    bullet_points [
      "Identity documents (e.g., CIN, passport, selfie)",
      "Contact details (e.g., email, phone number)",
      "Device and usage data (e.g., IP address, browser type)"
    ]

    section_title "2. How We Use Your Data"
    body_text "Your data is used to:"
    bullet_points [
      "Verify your identity for BonID services.",
      "Communicate with you about your account.",
      "Improve our platform’s security and functionality."
    ]
    body_text "We do not sell or share your data with third parties for marketing purposes."

    section_title "3. Data Retention"
    body_text "We retain your data only as long as necessary for verification or legal compliance. You may request deletion of your data at any time, subject to applicable laws."

    section_title "4. Data Security"
    body_text "We employ industry-standard encryption and security practices to protect your data from unauthorized access, including secure storage and regular audits."

    section_title "5. Your Rights"
    body_text "You have the right to:"
    bullet_points [
      "Access your personal data.",
      "Request updates or corrections.",
      "Request deletion of your data.",
      "Opt out of non-essential communications."
    ]

    section_title "6. Third-Party Sharing"
    body_text "We may share data with trusted partners only for verification purposes (e.g., government agencies for identity checks). Such partners are bound by strict confidentiality agreements."

    section_title "7. Contact Us"
    body_text "For privacy inquiries, contact us at:"
    bullet_points [
      "Email: support@bonid.ht",
      "Website: https://bonid.ht",
      "Address: BonID, 123 Haiti Street, Port-au-Prince, Haiti"
    ]

    section_title "8. Changes to This Policy"
    body_text "This Privacy Policy may be updated periodically. The last update was on #{Date.today.strftime('%B %d, %Y')}."

    # Footer
    footer
  end

  private

  def header
    # Header bar with Haitian Blue
    fill_color '00209F' # Haitian Blue
    fill_rectangle [0, cursor], bounds.width, 60
    fill_color 'D21034' # Haitian Red (subtle accent line)
    fill_rectangle [0, cursor - 60], bounds.width, 2
    fill_color 'FFFFFF' # Pure White
    header_text = "BonID Privacy Policy"
    text_width = width_of(header_text, size: 24, style: :bold)
    x_position = (bounds.width - text_width) / 2
    draw_text header_text, size: 24, style: :bold, at: [x_position, cursor - 40], color: 'FFFFFF'

    # Optional: Add Haiti flag image if available
    if File.exist?(Rails.root.join('app', 'assets', 'images', 'haiti_flag.svg'))
      image Rails.root.join('app', 'assets', 'images', 'haiti_flag.svg'), at: [bounds.width - 50, cursor - 10], width: 40, height: 40
    end
  end

  def section_title(title)
    move_down 25
    stroke_color '1A936F' # Palm Green
    stroke_horizontal_rule
    move_down 10
    text title, size: 16, style: :bold, color: '3366CC' # Ocean Blue
    move_down 8
  end

  def body_text(text)
    text text, size: 12, align: :justify, color: '343A40' # Dark Gray
    move_down 8
  end

  def bullet_points(points)
    move_down 10
    points.each do |point|
      text "• #{point}", size: 12, indent_paragraphs: 20, color: '343A40' # Dark Gray
    end
    move_down 10
  end

  def footer
    # Footer at page bottom
    bounding_box([0, 30], width: bounds.width, height: 30) do
      text "Certified by BonID | Generated on #{Date.today.strftime('%B %d, %Y')}", size: 10, style: :italic, align: :center, color: '6C757D' # Mid Gray
    end
  end
end