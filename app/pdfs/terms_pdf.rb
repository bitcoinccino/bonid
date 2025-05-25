# app/pdfs/terms_pdf.rb
class TermsPdf < Prawn::Document
  def initialize
    super(margin: 50)
    stroke_color '6C757D' # Mid Gray for bounds
    stroke_bounds

    font "Helvetica"

    # Header
    header
    move_down 80 # Move below 60px header + padding

    # Main title
    text "BonID Terms of Use", size: 28, style: :bold, align: :center, color: '3366CC' # Ocean Blue
    move_down 25

    # Subtitle
    text "By using BonID, you agree to these terms governing our services.", align: :center, size: 12, color: '343A40' # Dark Gray
    move_down 35

    # Content sections
    section_title "1. Acceptance of Terms"
    body_text "By accessing or using BonID, you agree to comply with these Terms of Use and any applicable laws."

    section_title "2. User Responsibilities"
    body_text "As a BonID user, you agree to:"
    bullet_points [
      "Provide accurate and complete information during registration and verification.",
      "Use BonID only for lawful purposes and in accordance with these Terms.",
      "Protect your account credentials and report any unauthorized access immediately."
    ]

    section_title "3. Restrictions"
    body_text "You agree not to:"
    bullet_points [
      "Misuse BonID for illegal or unauthorized activities.",
      "Attempt to access or tamper with other users’ data.",
      "Use automated tools to scrape or exploit BonID services."
    ]

    section_title "4. Intellectual Property"
    body_text "All content, logos, and trademarks on BonID are the property of BonID or its licensors. You may not use them without prior written consent."

    section_title "5. Account Termination"
    body_text "BonID reserves the right to suspend or terminate your account for violations of these Terms, including providing false information or engaging in prohibited activities."

    section_title "6. Dispute Resolution"
    body_text "Any disputes arising from your use of BonID will be governed by the laws of Haiti. You agree to resolve disputes through mediation before pursuing legal action."

    section_title "7. Contact Us"
    body_text "For questions about these Terms, contact us at:"
    bullet_points [
      "Email: support@bonid.ht",
      "Website: https://bonid.ht",
      "Address: BonID, 123 Haiti Street, Port-au-Prince, Haiti"
    ]

    section_title "8. Changes to These Terms"
    body_text "These Terms may be updated periodically. The last update was on #{Date.today.strftime('%B %d, %Y')}."

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
    header_text = "BonID Terms of Use"
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