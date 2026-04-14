#!/usr/bin/env python3
"""Generate BonVote White Paper PDF."""

from reportlab.lib.pagesizes import letter
from reportlab.lib.units import inch
from reportlab.lib.colors import HexColor, white, black
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.enums import TA_CENTER, TA_JUSTIFY, TA_LEFT
from reportlab.platypus import (
    SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle,
    PageBreak, KeepTogether, HRFlowable
)
from reportlab.platypus.flowables import Flowable
import os

# ── Colors ──────────────────────────────────────────────
BRAND_BLUE = HexColor("#1E3A5F")
BRAND_ACCENT = HexColor("#2563EB")
LIGHT_BLUE = HexColor("#EFF6FF")
LIGHT_GRAY = HexColor("#F8FAFC")
BORDER_GRAY = HexColor("#E2E8F0")
TEXT_PRIMARY = HexColor("#0F172A")
TEXT_SECONDARY = HexColor("#475569")
SUCCESS_GREEN = HexColor("#059669")
WARNING_AMBER = HexColor("#D97706")
DANGER_RED = HexColor("#DC2626")
HAITI_BLUE = HexColor("#00209F")
HAITI_RED = HexColor("#D21034")

OUTPUT = os.path.expanduser("~/Desktop/BonVote_White_Paper_2026.pdf")

# ── Styles ──────────────────────────────────────────────
styles = getSampleStyleSheet()

styles.add(ParagraphStyle(
    'DocTitle', parent=styles['Title'],
    fontSize=28, leading=34, textColor=white,
    alignment=TA_CENTER, spaceAfter=6,
    fontName='Helvetica-Bold'
))

styles.add(ParagraphStyle(
    'DocSubtitle', parent=styles['Normal'],
    fontSize=14, leading=18, textColor=HexColor("#CBD5E1"),
    alignment=TA_CENTER, spaceAfter=20,
    fontName='Helvetica'
))

styles.add(ParagraphStyle(
    'SectionTitle', parent=styles['Heading1'],
    fontSize=18, leading=24, textColor=BRAND_BLUE,
    spaceBefore=24, spaceAfter=12,
    fontName='Helvetica-Bold',
    borderPadding=(0, 0, 4, 0),
))

styles.add(ParagraphStyle(
    'SubSection', parent=styles['Heading2'],
    fontSize=13, leading=17, textColor=BRAND_ACCENT,
    spaceBefore=16, spaceAfter=8,
    fontName='Helvetica-Bold'
))

styles.add(ParagraphStyle(
    'Body', parent=styles['Normal'],
    fontSize=10.5, leading=15, textColor=TEXT_PRIMARY,
    alignment=TA_JUSTIFY, spaceAfter=8,
    fontName='Helvetica'
))

styles.add(ParagraphStyle(
    'BodyBold', parent=styles['Normal'],
    fontSize=10.5, leading=15, textColor=TEXT_PRIMARY,
    alignment=TA_JUSTIFY, spaceAfter=8,
    fontName='Helvetica-Bold'
))

styles.add(ParagraphStyle(
    'BulletItem', parent=styles['Normal'],
    fontSize=10.5, leading=15, textColor=TEXT_PRIMARY,
    leftIndent=24, spaceAfter=4,
    bulletIndent=12, bulletFontSize=10,
    fontName='Helvetica'
))

styles.add(ParagraphStyle(
    'Caption', parent=styles['Normal'],
    fontSize=9, leading=12, textColor=TEXT_SECONDARY,
    alignment=TA_CENTER, spaceAfter=12,
    fontName='Helvetica-Oblique'
))

styles.add(ParagraphStyle(
    'Footer', parent=styles['Normal'],
    fontSize=8, leading=10, textColor=TEXT_SECONDARY,
    alignment=TA_CENTER,
    fontName='Helvetica'
))

styles.add(ParagraphStyle(
    'TableCell', parent=styles['Normal'],
    fontSize=9.5, leading=13, textColor=TEXT_PRIMARY,
    fontName='Helvetica'
))

styles.add(ParagraphStyle(
    'TableHeader', parent=styles['Normal'],
    fontSize=9.5, leading=13, textColor=white,
    fontName='Helvetica-Bold'
))

styles.add(ParagraphStyle(
    'Quote', parent=styles['Normal'],
    fontSize=11, leading=16, textColor=BRAND_BLUE,
    leftIndent=36, rightIndent=36,
    spaceBefore=12, spaceAfter=12,
    fontName='Helvetica-Oblique',
    alignment=TA_CENTER,
))


# ── Custom Flowables ────────────────────────────────────
class CoverPage(Flowable):
    """Full-page cover with brand colors."""
    def __init__(self, width, height):
        super().__init__()
        self.width = width
        self.height = height

    def wrap(self, availWidth, availHeight):
        return 0, 0

    def draw(self):
        c = self.canv
        # Background - draw full page
        c.setFillColor(BRAND_BLUE)
        c.rect(-inch, -letter[1] + 72, letter[0], letter[1], fill=1, stroke=0)

        # Accent stripe (Haiti flag colors)
        c.setFillColor(HAITI_RED)
        c.rect(-inch, -letter[1] + 72, letter[0], 8, fill=1, stroke=0)
        c.setFillColor(HAITI_BLUE)
        c.rect(-inch, -letter[1] + 80, letter[0], 8, fill=1, stroke=0)


class InfoBox(Flowable):
    """Colored info box."""
    def __init__(self, text, bg_color=LIGHT_BLUE, border_color=BRAND_ACCENT, width=None):
        super().__init__()
        self.text = text
        self.bg_color = bg_color
        self.border_color = border_color
        self._width = width or 6.5 * inch

    def wrap(self, availWidth, availHeight):
        self.para = Paragraph(self.text, ParagraphStyle(
            'InfoBoxText', parent=styles['Body'],
            fontSize=10, leading=14,
        ))
        w, h = self.para.wrap(self._width - 24, availHeight)
        self._height = h + 16
        return self._width, self._height

    def draw(self):
        c = self.canv
        c.setFillColor(self.bg_color)
        c.setStrokeColor(self.border_color)
        c.setLineWidth(1.5)
        c.roundRect(0, 0, self._width, self._height, 4, fill=1, stroke=1)
        self.para.drawOn(c, 12, 8)


def make_table(headers, rows, col_widths=None):
    """Create a styled table."""
    header_cells = [Paragraph(h, styles['TableHeader']) for h in headers]
    data = [header_cells]
    for row in rows:
        data.append([Paragraph(str(cell), styles['TableCell']) for cell in row])

    if not col_widths:
        col_widths = [6.5 * inch / len(headers)] * len(headers)

    t = Table(data, colWidths=col_widths, repeatRows=1)
    t.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, 0), BRAND_BLUE),
        ('TEXTCOLOR', (0, 0), (-1, 0), white),
        ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
        ('FONTSIZE', (0, 0), (-1, 0), 9.5),
        ('BOTTOMPADDING', (0, 0), (-1, 0), 8),
        ('TOPPADDING', (0, 0), (-1, 0), 8),
        ('BACKGROUND', (0, 1), (-1, -1), white),
        ('ROWBACKGROUNDS', (0, 1), (-1, -1), [white, LIGHT_GRAY]),
        ('GRID', (0, 0), (-1, -1), 0.5, BORDER_GRAY),
        ('VALIGN', (0, 0), (-1, -1), 'TOP'),
        ('TOPPADDING', (0, 1), (-1, -1), 6),
        ('BOTTOMPADDING', (0, 1), (-1, -1), 6),
        ('LEFTPADDING', (0, 0), (-1, -1), 8),
        ('RIGHTPADDING', (0, 0), (-1, -1), 8),
    ]))
    return t


def add_page_number(canvas, doc):
    """Add page numbers and footer."""
    canvas.saveState()
    canvas.setFont('Helvetica', 8)
    canvas.setFillColor(TEXT_SECONDARY)
    canvas.drawCentredString(
        letter[0] / 2, 36,
        f"BonVote White Paper  |  Page {doc.page}  |  Confidentiel / Public"
    )
    # Top line
    canvas.setStrokeColor(BORDER_GRAY)
    canvas.setLineWidth(0.5)
    canvas.line(inch, letter[1] - 54, letter[0] - inch, letter[1] - 54)
    canvas.restoreState()


# ── Build Document ──────────────────────────────────────
doc = SimpleDocTemplate(
    OUTPUT,
    pagesize=letter,
    topMargin=72,
    bottomMargin=60,
    leftMargin=inch,
    rightMargin=inch,
    title="BonVote: Haiti's First Cryptographic Election System",
    author="Verifyem",
    subject="White Paper - Election Technology for Haiti",
)

story = []
W = letter[0] - 2 * inch  # usable width

# ════════════════════════════════════════════════════════
# COVER PAGE
# ════════════════════════════════════════════════════════
story.append(CoverPage(letter[0], letter[1]))
story.append(Spacer(1, 40))
story.append(Paragraph("BonVote", styles['DocTitle']))
story.append(Spacer(1, 8))
story.append(Paragraph(
    "Haiti's First Cryptographic Election Management System",
    styles['DocSubtitle']
))
story.append(Spacer(1, 24))
story.append(Paragraph(
    "Premye Sistèm Eleksyon Kriptografik Ayiti",
    ParagraphStyle('CreoleSubtitle', parent=styles['DocSubtitle'],
                   fontSize=12, textColor=HexColor("#94A3B8"))
))
story.append(Spacer(1, 60))

# Cover details
cover_details = [
    ["White Paper", "Version 1.0  |  March 2026"],
    ["Authors", "Verifyem Engineering"],
    ["Classification", "Public Distribution"],
    ["Legal Basis", "Décret Électoral du 1er Décembre 2025"],
]
for label, value in cover_details:
    story.append(Paragraph(
        f"<b>{label}:</b>  {value}",
        ParagraphStyle('CoverDetail', parent=styles['DocSubtitle'],
                       fontSize=10, textColor=HexColor("#94A3B8"),
                       spaceAfter=6)
    ))

story.append(PageBreak())

# ════════════════════════════════════════════════════════
# TABLE OF CONTENTS
# ════════════════════════════════════════════════════════
story.append(Paragraph("Table of Contents", styles['SectionTitle']))
story.append(Spacer(1, 8))

toc_items = [
    ("1", "Executive Summary"),
    ("2", "The Problem: Haiti's Electoral Crisis"),
    ("3", "What is BonVote?"),
    ("4", "How BonVote Works"),
    ("5", "System Architecture"),
    ("6", "Security Model"),
    ("7", "The Electoral Calendar"),
    ("8", "Candidate Registration"),
    ("9", "Voting Day: From Ballot to Tally"),
    ("10", "Multi-Signature Decryption Ceremony"),
    ("11", "Diaspora Voting"),
    ("12", "Cost Analysis"),
    ("13", "Advantages for the Haitian Government"),
    ("14", "Compliance with Décret Électoral"),
    ("15", "Deployment Roadmap"),
    ("16", "Conclusion"),
]
for num, title in toc_items:
    story.append(Paragraph(
        f"<b>{num}.</b>  {title}",
        ParagraphStyle('TOCItem', parent=styles['Body'],
                       leftIndent=12, spaceAfter=6, fontSize=11)
    ))

story.append(PageBreak())

# ════════════════════════════════════════════════════════
# 1. EXECUTIVE SUMMARY
# ════════════════════════════════════════════════════════
story.append(Paragraph("1. Executive Summary", styles['SectionTitle']))

story.append(Paragraph(
    "BonVote is Haiti's first integrated, cryptographically secure election management system. "
    "Built on the BonID national digital identity platform, it replaces Haiti's entirely manual "
    "election process — paper ballots, indelible ink, and weeks of hand tabulation — with a modern, "
    "transparent, and mathematically verifiable system.",
    styles['Body']
))

story.append(Paragraph(
    "Haiti has not held a national election since the disputed 2015-2016 cycle, which cost over "
    "$55 million USD (funded almost entirely by international donors) and produced results that took "
    "months to certify amid widespread allegations of fraud. The country has been governed without "
    "elected representatives for years. The 2025-2026 election cycle, mandated by the Décret Électoral "
    "of December 1, 2025, presents an opportunity to fundamentally modernize how Haiti conducts elections.",
    styles['Body']
))

story.append(InfoBox(
    "<b>Key Innovation:</b> BonVote uses zero-knowledge proofs and homomorphic encryption to ensure "
    "that votes are counted correctly without ever revealing how any individual voted. The server "
    "never sees the plaintext vote. Results can only be decrypted through a 5-of-9 multi-signature "
    "ceremony by CEP (Conseil Électoral Provisoire) members, each verified by biometric liveness detection."
))
story.append(Spacer(1, 8))

story.append(Paragraph(
    "BonVote reduces the cost of a full election cycle from $55-70 million to approximately $3-6 million "
    "— a 90% reduction — while simultaneously increasing transparency, eliminating ballot fraud, and "
    "enabling 2+ million Haitians in the diaspora to vote for the first time.",
    styles['Body']
))

story.append(PageBreak())

# ════════════════════════════════════════════════════════
# 2. THE PROBLEM
# ════════════════════════════════════════════════════════
story.append(Paragraph("2. The Problem: Haiti's Electoral Crisis", styles['SectionTitle']))

story.append(Paragraph("2.1 The Current State", styles['SubSection']))
story.append(Paragraph(
    "Haiti's last real national elections (2015-2016) relied on an almost entirely manual process. "
    "The only technology used was Dermalog biometric systems run by the Office National d'Identification (ONI) "
    "for voter registration. Everything else — voting, counting, tabulation — was done by hand.",
    styles['Body']
))

story.append(make_table(
    ["Component", "What Haiti Used (2015-2016)", "Risk"],
    [
        ["Voter Registry", "Dermalog biometrics (ONI/CIN)", "Functional but isolated"],
        ["Voting", "Paper ballots + ballot boxes + indelible ink", "Stuffing, loss, theft"],
        ["Counting", "Manual hand count at polling stations", "Human error, manipulation"],
        ["Tabulation", "Manual double-entry at CTV (Centre de Tabulation)", "Slow, error-prone"],
        ["Results", "Excel spreadsheets + internal databases", "No cryptographic proof"],
        ["Disputes", "Paper-based complaints to BCEN", "Months of delays"],
    ],
    col_widths=[1.3*inch, 2.2*inch, 3*inch]
))
story.append(Spacer(1, 8))

story.append(Paragraph("2.2 The Cost Problem", styles['SubSection']))
story.append(Paragraph(
    "The 2015-2016 election cycle cost approximately $55-70 million USD, funded almost entirely by "
    "international donors (USAID, Canada, EU, OAS/UNDP). Haiti cannot independently fund its own "
    "elections at this cost level. This creates a dependency that undermines sovereignty and subjects "
    "the electoral calendar to donor timelines.",
    styles['Body']
))

story.append(make_table(
    ["Cost Center", "Estimated Cost (USD)", "% of Total"],
    [
        ["Paper ballots (printing + distribution)", "$8-12M", "15-17%"],
        ["Polling station staff (40,000-60,000 temp workers)", "$12-18M", "22-26%"],
        ["Logistics and transport", "$10-15M", "18-21%"],
        ["Tabulation centers (CTV)", "$3-5M", "5-7%"],
        ["Security (PNH + MINUSTAH escort)", "$5-8M", "9-11%"],
        ["Indelible ink + supplies", "$2-3M", "3-4%"],
        ["Training", "$3-5M", "5-7%"],
        ["Second round (near-full repeat)", "$15-20M", "27-29%"],
        ["TOTAL", "$55-70M", "100%"],
    ],
    col_widths=[3*inch, 1.8*inch, 1.7*inch]
))

story.append(Spacer(1, 8))
story.append(Paragraph("2.3 The Trust Problem", styles['SubSection']))
story.append(Paragraph(
    "Multiple Haitian elections have been marred by allegations of fraud, ballot stuffing, and result "
    "manipulation. The 2015 presidential election was annulled after an independent commission found "
    "\"massive fraud.\" The fundamental issue is that paper-based elections offer no mathematical proof "
    "that results are correct. Citizens must trust the process — and that trust has been eroded.",
    styles['Body']
))

story.append(Paragraph("2.4 The Diaspora Problem", styles['SubSection']))
story.append(Paragraph(
    "An estimated 2+ million Haitians live abroad (United States, Canada, France, Dominican Republic, "
    "Chile, Brazil, and others). Under the current system, they have no mechanism to vote. The Décret "
    "Électoral of 2025 explicitly provides for diaspora voting through consular stations, but "
    "implementing this with paper ballots across 40+ countries is logistically impossible.",
    styles['Body']
))

story.append(PageBreak())

# ════════════════════════════════════════════════════════
# 3. WHAT IS BONVOTE?
# ════════════════════════════════════════════════════════
story.append(Paragraph("3. What is BonVote?", styles['SectionTitle']))

story.append(Paragraph(
    "BonVote is the election module of BonID — Haiti's national digital identity verification platform. "
    "It is a complete Election Management System (EMS) that handles every phase of the electoral cycle: "
    "from party registration and candidate approval through voting day, cryptographic tabulation, "
    "multi-signature result certification, and public audit.",
    styles['Body']
))

story.append(InfoBox(
    "<b>BonVote is NOT electronic voting in the traditional sense.</b> Unlike systems like Smartmatic "
    "or Dominion that use proprietary counting machines, BonVote uses open cryptographic protocols "
    "(Schnorr ZKP, Pedersen commitments, AES-256-GCM, Shamir's Secret Sharing) where any "
    "mathematician can verify the integrity of results independently. The server never sees how "
    "anyone voted."
))
story.append(Spacer(1, 8))

story.append(Paragraph("3.1 Core Principles", styles['SubSection']))

principles = [
    "<b>Zero-Knowledge Privacy:</b> The vote is encrypted on the voter's device before it ever reaches "
    "the server. The server stores, counts, and certifies votes without ever knowing their content.",

    "<b>Mathematical Verifiability:</b> Every ballot produces a Merkle-tree hash. Any observer (OAS, UN, "
    "citizen) can independently verify that no ballots were added, removed, or modified.",

    "<b>Multi-Signature Decryption:</b> Results can only be decrypted when 5 of 9 authorized CEP members "
    "each contribute their key shard in a public ceremony with biometric verification.",

    "<b>Diaspora Inclusion:</b> Haitians abroad vote through the same app, with ballots routed "
    "to the correct constituency based on their BonID location code.",

    "<b>Sovereign Infrastructure:</b> No international vendor lock-in. Haiti owns and operates the "
    "system. Cost drops from $55M to $3-6M per election cycle.",
]
for p in principles:
    story.append(Paragraph(p, styles['BulletItem'], bulletText='\u2022'))

story.append(PageBreak())

# ════════════════════════════════════════════════════════
# 4. HOW BONVOTE WORKS
# ════════════════════════════════════════════════════════
story.append(Paragraph("4. How BonVote Works", styles['SectionTitle']))

story.append(Paragraph(
    "BonVote operates through six sequential phases, each gated by the official CEP electoral calendar.",
    styles['Body']
))

phases_data = [
    ["Phase 1", "Party Registration\n(Enrejistreman Pati Politik)", "Political parties and groupings submit registration with required documents. CEP reviews and approves. Articles 143-145 of the Décret Électoral.", "Mar 2 - Mar 12, 2026"],
    ["Phase 2", "Candidate Registration\n(Depo Kandida)", "Candidates submit 12 required documents, pay registration fees (800K G president, 120K G senator, 60K G deputy), and receive a cryptographic recepisse. BonID auto-fills verified data.", "Apr 13 - May 15, 2026"],
    ["Phase 3", "Voter Registration\n(Lis Elektoral)", "Electoral roll built from CIN-verified BonID users. Cross-referenced with ONI biometric database. VoterEligibilityRecord created per voter per election.", "Apr 1 - Jun 29, 2026"],
    ["Phase 4", "Campaign Period\n(Kanpay Elektoral)", "Official campaign period. System provides real-time analytics on registration stats, voter roll completeness, and constituency coverage.", "May 19 - Aug 28, 2026"],
    ["Phase 5", "Voting Day\n(Jounen Vòt)", "12-hour voting window. Voters authenticate via BonID app with liveness verification, receive cryptographic ballot, vote encrypted on-device, cast via API. Real-time CEP dashboard tracks participation.", "Aug 30, 2026"],
    ["Phase 6", "Results & Certification\n(Rezilta & Sètifikasyon)", "Multi-signature ceremony (5-of-9 CEP members). Key shards combined via Shamir's Secret Sharing. Results decrypted and published with Merkle root integrity proof.", "Sep 2 - Oct 3, 2026"],
]

story.append(make_table(
    ["", "Phase", "Description", "Official Date"],
    phases_data,
    col_widths=[0.6*inch, 1.5*inch, 3.2*inch, 1.2*inch]
))

story.append(PageBreak())

# ════════════════════════════════════════════════════════
# 5. SYSTEM ARCHITECTURE
# ════════════════════════════════════════════════════════
story.append(Paragraph("5. System Architecture", styles['SectionTitle']))

story.append(Paragraph("5.1 Technology Stack", styles['SubSection']))

story.append(make_table(
    ["Layer", "Technology", "Purpose"],
    [
        ["Backend", "Ruby on Rails 7.1", "API, business logic, election lifecycle management"],
        ["Database", "PostgreSQL", "Immutable ballot ledger, voter rolls, candidate records"],
        ["Cache", "Redis", "Geocoder cache, challenge nonces, session management"],
        ["Real-time", "ActionCable (WebSockets)", "Live vote count broadcast to CEP dashboard"],
        ["Encryption", "AES-256-GCM + RSA", "Vote encryption with CEP public key"],
        ["Zero-Knowledge", "Schnorr ZKP + Pedersen Commitments", "Vote privacy without revealing content"],
        ["Key Management", "Shamir's Secret Sharing (5-of-9)", "Distributed decryption keys among CEP members"],
        ["Integrity", "SHA-256 Merkle Trees", "Tamper-evident ballot ledger"],
        ["Identity", "BonID + Dermalog/ONI CIN", "Voter verification via national ID"],
        ["Geolocation", "IPInfo.io (cached 30 days)", "Diaspora routing, location flagging"],
    ],
    col_widths=[1.3*inch, 2.2*inch, 3*inch]
))
story.append(Spacer(1, 8))

story.append(Paragraph("5.2 Data Model", styles['SubSection']))
story.append(Paragraph(
    "The election system is built around a central BonvoteElection record with the following structure:",
    styles['Body']
))

story.append(make_table(
    ["Entity", "Purpose", "Key Fields"],
    [
        ["BonvoteElection", "Election event (round 1 or 2)", "title, type, round, status, election_date, cep_public_key"],
        ["ElectionConstituency", "Geographic voting area", "position (president/senator/deputy), department, commune"],
        ["ElectionCandidate", "Registered nominee", "full_name, position, party, documents, fee, recepisse"],
        ["ElectionBallot", "Immutable vote record", "nullifier, encrypted_choice, zkp_proof, ballot_hash"],
        ["ElectionSignature", "Multi-sig ceremony record", "bonid, role, key_shard_hash, liveness_verified"],
        ["ElectoralCalendar", "Phase timeline", "phase, start_date, end_date, responsible_body"],
        ["VoterEligibilityRecord", "Voter roll entry", "bonid, cin_number, department, eligibility_status"],
        ["ElectionPartyRegistration", "Party/grouping registration", "party_name, acronym, type, status"],
    ],
    col_widths=[1.8*inch, 1.8*inch, 2.9*inch]
))

story.append(PageBreak())

# ════════════════════════════════════════════════════════
# 6. SECURITY MODEL
# ════════════════════════════════════════════════════════
story.append(Paragraph("6. Security Model", styles['SectionTitle']))

story.append(Paragraph(
    "BonVote implements defense-in-depth across seven layers. No single point of compromise can "
    "alter election results.",
    styles['Body']
))

story.append(Paragraph("6.1 Cryptographic Layers", styles['SubSection']))

security_layers = [
    ["Layer 1", "Client-Side Encryption", "AES-256-GCM", "Votes encrypted on voter's device with CEP public key. Server never sees plaintext."],
    ["Layer 2", "Zero-Knowledge Proofs", "Schnorr ZKP", "Voter proves they know their vote without revealing it. challenge + response + public_commitment."],
    ["Layer 3", "Pedersen Commitments", "Homomorphic", "Vote hidden in a commitment that allows aggregation without decryption."],
    ["Layer 4", "Nullifier System", "SHA-256 derived", "One vote per voter per election. Cannot be linked back to voter identity."],
    ["Layer 5", "Merkle Tree Ledger", "SHA-256", "Every ballot hashed into a tree. Any tampering invalidates the root."],
    ["Layer 6", "Multi-Signature", "Shamir's 5-of-9", "No single person can decrypt results. 5 of 9 CEP members required."],
    ["Layer 7", "Biometric Verification", "BonID Liveness", "Each signatory verified by face match + liveness detection at ceremony."],
]

story.append(make_table(
    ["Layer", "Mechanism", "Algorithm", "Protection"],
    security_layers,
    col_widths=[0.7*inch, 1.5*inch, 1.3*inch, 3*inch]
))
story.append(Spacer(1, 8))

story.append(Paragraph("6.2 Anti-Fraud Guarantees", styles['SubSection']))

guarantees = [
    "<b>No ballot stuffing:</b> Every ballot requires a unique nullifier derived from the voter's identity. "
    "Duplicate nullifiers are rejected idempotently (same receipt returned, no double-count).",

    "<b>No vote alteration:</b> Votes are encrypted client-side with AES-256-GCM. The auth_tag ensures "
    "any modification is detected. The Merkle root changes if any ballot is altered.",

    "<b>No result manipulation:</b> Results require 5-of-9 multi-signature ceremony. Each signatory "
    "is biometrically verified. Key shards are combined via Shamir's Secret Sharing.",

    "<b>No identity fraud:</b> Voters authenticate via BonID (CIN-verified, biometric liveness). "
    "The nullifier system prevents one person from voting twice without revealing who voted.",

    "<b>No covert deletion:</b> The Merkle tree ledger is append-only. International observers can "
    "download the full ledger (CSV of ballot hashes) and independently verify integrity.",

    "<b>Geolocation monitoring:</b> IP country is compared to BonID location code. Mismatches are "
    "flagged for CEP review but do not block voting (voter may be traveling).",
]
for g in guarantees:
    story.append(Paragraph(g, styles['BulletItem'], bulletText='\u2022'))

story.append(PageBreak())

# ════════════════════════════════════════════════════════
# 7. ELECTORAL CALENDAR
# ════════════════════════════════════════════════════════
story.append(Paragraph("7. The Electoral Calendar", styles['SectionTitle']))

story.append(Paragraph(
    "BonVote implements the official CEP 2026 electoral calendar as a first-class data structure. "
    "The calendar drives the entire system — gating candidate registration, voter enrollment, "
    "and voting windows automatically.",
    styles['Body']
))

calendar_data = [
    ["Enrejistreman Pati Politik", "party_registration", "Mar 2 - Mar 12", "CEP"],
    ["Depo Kandida", "candidate_registration", "Apr 13 - May 15", "CEP"],
    ["Enrejistreman Elektè", "voter_registration", "Apr 1 - Jun 29", "ONI/CEP"],
    ["Kanpay Elektoral (1ye tou)", "campaign", "May 19 - Aug 28", "Candidates"],
    ["Peryòd Silans", "silence_period", "Aug 29 - Aug 30", "CEP"],
    ["Jou Vòt (1ye tou)", "voting_day", "Aug 30", "CEP/BEC"],
    ["Tabulasyon Rezilta", "tabulation", "Aug 30 - Sep 1", "CTV"],
    ["Rezilta Preliminè", "preliminary_results", "Sep 2 - Sep 8", "CEP"],
    ["Kontestasyon", "disputes", "Sep 3 - Oct 2", "BCEN"],
    ["Rezilta Definitif (1ye tou)", "final_results", "Oct 3", "CEP"],
    ["Kanpay Dezyèm Tou", "second_round_campaign", "Nov 6 - Dec 5", "Candidates"],
    ["Jou Vòt Dezyèm Tou", "second_round_voting", "Dec 6", "CEP/BEC"],
    ["Rezilta Definitif Dezyèm Tou", "second_round_results", "Jan 7, 2027", "CEP"],
]

story.append(make_table(
    ["Phase Name (Kreyòl)", "System Key", "Dates", "Body"],
    calendar_data,
    col_widths=[2.2*inch, 1.6*inch, 1.5*inch, 1.2*inch]
))
story.append(Spacer(1, 8))

story.append(InfoBox(
    "<b>Automatic Phase Gating:</b> The /enskri-kandida (candidate registration) portal automatically "
    "opens only during the candidate_registration phase and shows a friendly message otherwise. "
    "The sidebar displays the current phase with a live progress bar. This prevents candidates from "
    "submitting outside the legal window defined by the Décret Électoral."
))

story.append(PageBreak())

# ════════════════════════════════════════════════════════
# 8. CANDIDATE REGISTRATION
# ════════════════════════════════════════════════════════
story.append(Paragraph("8. Candidate Registration", styles['SectionTitle']))

story.append(Paragraph(
    "BonVote implements the full candidate registration flow per Articles 180-181 of the Décret Électoral, "
    "with BonID auto-population of verified data.",
    styles['Body']
))

story.append(Paragraph("8.1 Registration Flow", styles['SubSection']))
story.append(Paragraph(
    "draft -> submitted -> under_review -> approved (active on ballot) or rejected",
    ParagraphStyle('Flow', parent=styles['Body'], fontName='Courier',
                   fontSize=10, textColor=BRAND_ACCENT, alignment=TA_CENTER,
                   spaceBefore=8, spaceAfter=8)
))

story.append(Paragraph("8.2 Required Documents (Article 181)", styles['SubSection']))

docs_data = [
    ["1", "CIN oswa Sètifika ONI", "All candidates", "Auto-verified via BonID"],
    ["2", "Ak nesans / Ekstrè achiv", "All candidates", "Manual upload"],
    ["3", "Ekstrè kazye jidisyè (DCPJ)", "All candidates", "Manual upload"],
    ["4", "Kitans DGI (frè enskripsyon)", "All candidates", "Auto-checked if paid via BonID DGI"],
    ["5", "Atestasyon rezidans", "All candidates", "Auto-filled from BonID address"],
    ["6", "4 foto idantite", "All candidates", "Auto-checked if BonID photo attached"],
    ["7", "Atestasyon pwofesyon", "All candidates", "Manual upload"],
    ["8", "Pwopriyete imobilye", "President, Senator only", "Manual upload"],
    ["9", "Sètifika imigrasyon", "Conditional", "Manual upload"],
    ["10", "Dechaj (ansyen fonksyonè)", "Conditional", "Manual upload"],
    ["11", "Atestasyon pati politik", "Party/grouping only", "Linked to ElectionPartyRegistration"],
    ["12", "Petisyon 2% elektè", "Independent only", "Manual upload"],
]

story.append(make_table(
    ["#", "Document", "Required For", "BonID Integration"],
    docs_data,
    col_widths=[0.4*inch, 2*inch, 1.6*inch, 2.5*inch]
))
story.append(Spacer(1, 8))

story.append(Paragraph("8.3 Registration Fees", styles['SubSection']))
story.append(make_table(
    ["Position", "Fee (Gourdes)", "Fee (USD approx.)", "50% Reduction"],
    [
        ["President (Prezidan)", "800,000 G", "~$5,000", "Women, disabled, educators"],
        ["Senator (Senatè)", "120,000 G", "~$750", "Women, disabled, educators"],
        ["Deputy (Depite)", "60,000 G", "~$375", "Women, disabled, educators"],
    ],
    col_widths=[1.8*inch, 1.5*inch, 1.5*inch, 1.7*inch]
))

story.append(PageBreak())

# ════════════════════════════════════════════════════════
# 9. VOTING DAY
# ════════════════════════════════════════════════════════
story.append(Paragraph("9. Voting Day: From Ballot to Tally", styles['SectionTitle']))

story.append(Paragraph("9.1 Voter Authentication", styles['SubSection']))
steps = [
    "<b>Step 1 — Open BonID App:</b> Voter launches the BonID mobile application.",
    "<b>Step 2 — Liveness Verification:</b> Biometric face match + liveness detection confirms the physical person.",
    "<b>Step 3 — Eligibility Check:</b> API verifies: (a) BonID is verified, (b) CIN is on voter roll, "
    "(c) nullifier check confirms voter hasn't voted yet, (d) geolocation noted.",
    "<b>Step 4 — Ballot Routing:</b> Based on BonID location code (4th segment), voter receives the "
    "correct ballot: domestic (3 sections: President + Senator + Deputy) or diaspora (1 section: President only).",
    "<b>Step 5 — Vote on Device:</b> Voter selects candidates. The app generates: Schnorr ZKP proof, "
    "Pedersen commitment, AES-256-GCM encryption with CEP public key, nullifier, and ballot hash.",
    "<b>Step 6 — Cast:</b> Encrypted ballot sent to server via POST /api/v1/election/:id/cast. "
    "Server stores the encrypted blob without ever seeing the vote. Voter receives a ballot_hash receipt.",
]
for s in steps:
    story.append(Paragraph(s, styles['BulletItem'], bulletText='\u2022'))

story.append(Spacer(1, 8))
story.append(Paragraph("9.2 What the Server Stores (per ballot)", styles['SubSection']))

story.append(make_table(
    ["Field", "Content", "Reveals Vote?"],
    [
        ["nullifier", "SHA-256 hash (unique per voter per election)", "No"],
        ["encrypted_choice", "AES-256-GCM encrypted blob + IV + auth_tag", "No"],
        ["encrypted_key", "RSA-encrypted AES session key", "No"],
        ["zkp_commitment", "Pedersen commitment hiding the vote", "No"],
        ["zkp_proof", "Schnorr proof (challenge, response, public_commitment)", "No"],
        ["ballot_hash", "SHA-256 of entire ballot (voter receipt)", "No"],
        ["receipt_id", "Unique public identifier", "No"],
        ["channel", "remote / consulate / in_person", "No"],
        ["department_code", "From BonID location code", "No"],
        ["ip_country", "From IP geolocation (cached)", "No"],
        ["cast_at", "Timestamp", "No"],
    ],
    col_widths=[1.5*inch, 3.2*inch, 1.8*inch]
))
story.append(Spacer(1, 4))
story.append(Paragraph(
    "Note: The server stores 11 fields per ballot. None of them reveal the voter's choice.",
    styles['Caption']
))

story.append(Paragraph("9.3 Performance", styles['SubSection']))
story.append(Paragraph(
    "BonVote is engineered to handle Haiti's full voter base at peak load:",
    styles['Body']
))

story.append(make_table(
    ["Metric", "Value"],
    [
        ["Eligible voters", "~6 million"],
        ["Expected turnout (30-40%)", "~1.8 - 2.4 million votes"],
        ["Voting window", "12 hours (6 AM - 6 PM)"],
        ["Required throughput", "~2,500 - 3,300 votes/minute"],
        ["System capacity (4 workers x 4 threads)", "10,000 - 15,000 votes/minute"],
        ["Headroom factor", "3-5x required rate"],
        ["Geocoder optimization", "Cached 30 days via IpGeolocator service"],
        ["Broadcast optimization", "Async via BroadcastNewVoteJob (ActiveJob)"],
        ["Kiosk optimization", "Geolocation skipped (constituency known)"],
    ],
    col_widths=[3.2*inch, 3.3*inch]
))

story.append(PageBreak())

# ════════════════════════════════════════════════════════
# 10. MULTI-SIGNATURE CEREMONY
# ════════════════════════════════════════════════════════
story.append(Paragraph("10. Multi-Signature Decryption Ceremony", styles['SectionTitle']))

story.append(Paragraph(
    "Results cannot be decrypted by any single person. The Multi-Signature Ceremony requires "
    "5 of 9 authorized CEP signatories to each contribute their decryption key shard, verified "
    "by biometric liveness detection, in a public ceremony.",
    styles['Body']
))

story.append(Paragraph("10.1 Authorized Signatories", styles['SubSection']))

story.append(make_table(
    ["Role", "Title", "Type"],
    [
        ["cep_president", "Prezidan CEP", "Signatory (key holder)"],
        ["cep_vice_president", "Vis-Prezidan CEP", "Signatory (key holder)"],
        ["cep_secretary_general", "Sekretè Jeneral CEP", "Signatory (key holder)"],
        ["cep_member_1 through cep_member_6", "Manm Konsèy CEP (6 seats)", "Signatory (key holder)"],
        ["international_observer", "Obsèvatè Entènasyonal (OEA/ONU)", "Observer (non-signing)"],
        ["bonid_technical_director", "Direktè Teknik BonID", "Observer (non-signing)"],
    ],
    col_widths=[2.2*inch, 2.5*inch, 1.8*inch]
))
story.append(Spacer(1, 8))

story.append(Paragraph("10.2 Ceremony Protocol", styles['SubSection']))
ceremony_steps = [
    "<b>1. Identity Verification:</b> Each signatory scans their BonID QR code.",
    "<b>2. Liveness Check:</b> Biometric face match + anti-spoofing liveness detection confirms physical presence.",
    "<b>3. Key Shard Entry:</b> Signatory enters their unique decryption key shard (received separately via secure channel).",
    "<b>4. Signature Record:</b> ElectionSignature record created with: bonid (unique per election), role (unique per election), "
    "key_shard_hash (SHA-256, not plaintext), liveness_verified = true, signed_at timestamp.",
    "<b>5. Quorum Check:</b> After each signature, system checks: signatures >= 5? If yes, quorum met.",
    "<b>6. Key Reconstruction:</b> 5+ key shards combined via Shamir's Secret Sharing to reconstruct master decryption key.",
    "<b>7. Results Published:</b> Aggregate vote counts per candidate displayed with Merkle root integrity proof.",
]
for s in ceremony_steps:
    story.append(Paragraph(s, styles['BulletItem'], bulletText='\u2022'))

story.append(Spacer(1, 8))
story.append(InfoBox(
    "<b>Why 5-of-9?</b> This threshold ensures no faction of fewer than 5 CEP members can unilaterally "
    "access results, while allowing the ceremony to proceed even if up to 4 members are unavailable. "
    "This is the same threshold used by major financial institutions for multi-signature wallets.",
    bg_color=HexColor("#FEF3C7"), border_color=WARNING_AMBER
))

story.append(PageBreak())

# ════════════════════════════════════════════════════════
# 11. DIASPORA VOTING
# ════════════════════════════════════════════════════════
story.append(Paragraph("11. Diaspora Voting", styles['SectionTitle']))

story.append(Paragraph(
    "BonVote enables diaspora voting through two channels: the BonID mobile app (remote) and "
    "kiosk tablets at Haitian diplomatic missions (consulate). The BallotRoutingService automatically "
    "determines the correct ballot based on the voter's BonID location code.",
    styles['Body']
))

story.append(Paragraph("11.1 Ballot Routing Logic", styles['SubSection']))
story.append(Paragraph(
    "The BonID format encodes the voter's department or country at the 4th segment: "
    "VP-1970-M-<b>ND</b>-P2334-4EC (domestic, Nord department) vs "
    "VP-1985-F-<b>US</b>-K7721-9AB (diaspora, United States).",
    styles['Body']
))

story.append(make_table(
    ["Location Code", "Type", "Ballot Sections", "Positions"],
    [
        ["OU, ND, SD, AR, NE, NO, SE, CE, GA, NI", "Domestic", "3 sections", "President + Senator + Deputy"],
        ["US, CA, FR, DO, CL, BR, etc.", "Diaspora", "1 section", "President only"],
        ["HT (generic)", "Domestic (default)", "3 sections", "President + Senator + Deputy"],
    ],
    col_widths=[2.5*inch, 1*inch, 1.2*inch, 1.8*inch]
))
story.append(Spacer(1, 8))

story.append(Paragraph("11.2 Consulate Voting Stations", styles['SubSection']))
story.append(Paragraph(
    "BonVote supports 45+ Haitian diplomatic missions worldwide as voting stations. "
    "Each consulate operates a kiosk tablet with the BonID voting interface. "
    "Kiosk votes skip geolocation lookup (constituency known from station location) "
    "and are tagged with consulate_id and station_id for audit.",
    styles['Body']
))

story.append(PageBreak())

# ════════════════════════════════════════════════════════
# 12. COST ANALYSIS
# ════════════════════════════════════════════════════════
story.append(Paragraph("12. Cost Analysis", styles['SectionTitle']))

story.append(Paragraph("12.1 BonVote vs. Traditional Election Cost", styles['SubSection']))

story.append(make_table(
    ["Cost Center", "Traditional", "BonVote", "Savings"],
    [
        ["Paper ballots", "$8-12M", "$0", "$8-12M"],
        ["Polling station staff (40K+)", "$12-18M", "$500K (500 kiosk operators)", "$11.5-17.5M"],
        ["Logistics/transport", "$10-15M", "$0 (no physical materials)", "$10-15M"],
        ["Tabulation centers", "$3-5M", "$0 (automatic)", "$3-5M"],
        ["Security (ballot escort)", "$5-8M", "$200K (cybersecurity)", "$4.8-7.8M"],
        ["Indelible ink + supplies", "$2-3M", "$0 (nullifier system)", "$2-3M"],
        ["Training", "$3-5M", "$500K (500 operators)", "$2.5-4.5M"],
        ["Server infrastructure", "$0", "$100K", "-$100K"],
        ["Kiosk tablets (one-time)", "$0", "$1M (reusable)", "-$1M"],
        ["Public education campaign", "$0", "$1-2M", "-$1-2M"],
        ["Second round", "$15-20M", "$500K (marginal cost)", "$14.5-19.5M"],
        ["TOTAL", "$55-70M", "$3-6M", "$50-65M"],
    ],
    col_widths=[2*inch, 1.2*inch, 1.6*inch, 1.7*inch]
))
story.append(Spacer(1, 8))

story.append(Paragraph("12.2 Ten-Year Projection", styles['SubSection']))

story.append(make_table(
    ["", "Traditional (3 cycles)", "BonVote (3 cycles)", "Cumulative Savings"],
    [
        ["Year 1-2 (Cycle 1)", "$55-70M", "$5-6M (initial setup)", "$50-64M"],
        ["Year 4-5 (Cycle 2)", "$55-70M", "$3-4M (infrastructure exists)", "$102-130M"],
        ["Year 8-9 (Cycle 3)", "$55-70M", "$3-4M", "$154-196M"],
        ["10-YEAR TOTAL", "$165-210M", "$11-14M", "$154-196M"],
    ],
    col_widths=[1.8*inch, 1.6*inch, 1.8*inch, 1.3*inch]
))
story.append(Spacer(1, 8))

story.append(InfoBox(
    "<b>Cost per vote:</b> Traditional elections cost $25-35 per vote. BonVote costs $1.50-3.00 per vote. "
    "This represents a <b>90% reduction</b> in cost per vote — and eliminates Haiti's dependency on "
    "international donors to fund its own democratic process.",
    bg_color=HexColor("#ECFDF5"), border_color=SUCCESS_GREEN
))

story.append(PageBreak())

# ════════════════════════════════════════════════════════
# 13. ADVANTAGES FOR THE HAITIAN GOVERNMENT
# ════════════════════════════════════════════════════════
story.append(Paragraph("13. Advantages for the Haitian Government", styles['SectionTitle']))

advantages = [
    ("Electoral Sovereignty",
     "Haiti funds and operates its own elections at 1/10th the cost. No dependency on USAID, Canada, "
     "or EU donor timelines. The government controls the electoral calendar, infrastructure, and process."),

    ("Mathematical Trust",
     "Results are provably correct. Any mathematician, observer, or citizen can independently verify "
     "the Merkle root and confirm no ballots were added, removed, or altered. This replaces \"trust us\" "
     "with \"verify it yourself.\""),

    ("Fraud Elimination",
     "Ballot stuffing is mathematically impossible (nullifier system). Vote alteration is detectable "
     "(Merkle tree). Result manipulation requires compromising 5 of 9 biometrically-verified CEP members "
     "simultaneously."),

    ("Diaspora Inclusion",
     "2+ million Haitians abroad can vote for the first time. This increases democratic legitimacy "
     "and strengthens the connection between the diaspora and the homeland."),

    ("Instant Results",
     "Results are available within hours of polls closing, not weeks or months. The multi-signature "
     "ceremony can be completed within a single day. Disputes are resolved against cryptographic proof, "
     "not contested paper tallies."),

    ("Reusable Infrastructure",
     "The same system works for presidential, legislative, municipal, and referendum elections. "
     "Second rounds cost near-zero marginal cost. Party primaries and constitutional referendums "
     "use the same platform."),

    ("International Credibility",
     "Open cryptographic protocols allow international observers (OAS, UN, CARICOM) to independently "
     "verify election integrity. This positions Haiti as a technology leader in the Caribbean."),

    ("Reduced Political Violence",
     "Transparent, verifiable results reduce the incentive for post-election protests and violence. "
     "When citizens can verify their own vote was counted (ballot_hash receipt), trust increases."),

    ("Built on Existing Infrastructure",
     "BonVote leverages BonID and the existing ONI/Dermalog CIN system. No new national ID program required. "
     "The 6+ million CIN holders are already the voter base."),

    ("Complete Audit Trail",
     "Every action — registration, vote, signature, dispute — is logged with cryptographic integrity. "
     "Post-election audits are instantaneous rather than requiring manual review of paper records."),
]

for title, desc in advantages:
    story.append(KeepTogether([
        Paragraph(f"<b>{title}</b>", styles['BodyBold']),
        Paragraph(desc, styles['Body']),
        Spacer(1, 4),
    ]))

story.append(PageBreak())

# ════════════════════════════════════════════════════════
# 14. COMPLIANCE
# ════════════════════════════════════════════════════════
story.append(Paragraph("14. Compliance with Décret Électoral", styles['SectionTitle']))

story.append(Paragraph(
    "BonVote is designed to comply fully with the Décret Électoral du 1er Décembre 2025 and its revisions. "
    "Key compliance points:",
    styles['Body']
))

compliance_data = [
    ["Articles 143-145", "Party registration requirements", "ElectionPartyRegistration with full document verification"],
    ["Articles 180-181", "Candidate registration + 12 required documents", "12-document checklist with auto-verification via BonID"],
    ["Article 181 (fees)", "Registration fees by position + 50% reduction", "Automatic fee calculation: 800K/120K/60K G with reduction"],
    ["Absolute majority", "Two-round voting system", "create_runoff! duplicates top-2 candidates per constituency"],
    ["Secret ballot", "Vote secrecy requirement", "Zero-knowledge proofs + client-side encryption"],
    ["Universal suffrage", "All citizens 18+ can vote", "VoterEligibilityRecord from ONI/CIN database"],
    ["Diaspora voting", "Consular voting provision", "45+ diplomatic missions + remote app voting"],
    ["Transparency", "Observer access", "Public Merkle root + downloadable ledger (CSV)"],
    ["Dispute resolution", "BCEN complaint mechanism", "ElectionDispute model with cryptographic reference codes"],
]

story.append(make_table(
    ["Article/Provision", "Requirement", "BonVote Implementation"],
    compliance_data,
    col_widths=[1.5*inch, 2*inch, 3*inch]
))

story.append(PageBreak())

# ════════════════════════════════════════════════════════
# 15. DEPLOYMENT ROADMAP
# ════════════════════════════════════════════════════════
story.append(Paragraph("15. Deployment Roadmap", styles['SectionTitle']))

roadmap = [
    ["Phase 1\nMar-Apr 2026", "Foundation", "Election creation UI, electoral calendar generation, party registration portal, candidate registration with phase gating."],
    ["Phase 2\nApr-Jun 2026", "Voter Roll", "Build electoral roll from CIN-verified BonID users. Cross-reference with ONI database. VoterEligibilityRecord generation."],
    ["Phase 3\nJun-Jul 2026", "Voting Infrastructure", "BonID app ballot interface, cryptographic ballot generation (client-side), API load testing at 15,000 votes/min."],
    ["Phase 4\nJul-Aug 2026", "Security Audit", "Third-party penetration testing, cryptographic protocol review, CEP key ceremony rehearsal, disaster recovery testing."],
    ["Phase 5\nAug 30, 2026", "Election Day", "12-hour voting window, real-time CEP dashboard, consulate kiosk support, observer ledger access."],
    ["Phase 6\nSep-Oct 2026", "Certification", "Multi-signature ceremony, result publication, dispute resolution, public audit portal."],
    ["Phase 7\nDec 2026", "Second Round", "Automatic runoff election with near-zero marginal cost."],
]

story.append(make_table(
    ["Timeline", "Phase", "Deliverables"],
    roadmap,
    col_widths=[1.2*inch, 1.3*inch, 4*inch]
))

story.append(PageBreak())

# ════════════════════════════════════════════════════════
# 16. CONCLUSION
# ════════════════════════════════════════════════════════
story.append(Paragraph("16. Conclusion", styles['SectionTitle']))

story.append(Paragraph(
    "BonVote represents a paradigm shift in how Haiti conducts elections. By replacing a $55-70 million "
    "paper-based process with a $3-6 million cryptographically secure system, Haiti gains:",
    styles['Body']
))

conclusions = [
    "Electoral sovereignty — no longer dependent on international donors to fund democratic processes.",
    "Mathematical proof of results — replacing \"trust\" with \"verify.\"",
    "Diaspora inclusion — 2+ million Haitians abroad gain a democratic voice for the first time.",
    "Instant results — hours instead of months.",
    "Fraud elimination — not through promises, but through mathematics.",
    "Reusable infrastructure — the same system serves every future election at near-zero marginal cost.",
]
for c in conclusions:
    story.append(Paragraph(c, styles['BulletItem'], bulletText='\u2022'))

story.append(Spacer(1, 16))

story.append(Paragraph(
    "\"Demokrasi pa yon pwomès — se yon prèv matematik.\"",
    styles['Quote']
))
story.append(Paragraph(
    "Democracy is not a promise — it is a mathematical proof.",
    ParagraphStyle('QuoteTranslation', parent=styles['Caption'],
                   fontSize=10, textColor=TEXT_SECONDARY)
))

story.append(Spacer(1, 24))
story.append(HRFlowable(width="60%", color=BORDER_GRAY, thickness=1))
story.append(Spacer(1, 12))

story.append(Paragraph(
    "<b>BonVote</b> is a product of <b>Verifyem</b><br/>"
    "For inquiries: info@verifyem.ht<br/>"
    "Version 1.0 — March 2026",
    ParagraphStyle('Colophon', parent=styles['Caption'],
                   fontSize=9, textColor=TEXT_SECONDARY, spaceAfter=0)
))


# ── Build ───────────────────────────────────────────────
doc.build(story, onFirstPage=lambda c, d: None, onLaterPages=add_page_number)
print(f"White paper generated: {OUTPUT}")
