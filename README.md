# README

# BonID

Secure Digital Identity Infrastructure for Haiti

BonID is a digital identity verification platform designed to provide citizens, organizations, financial institutions, healthcare providers, and government agencies with a trusted and privacy-preserving method of identity verification.

The platform enables secure enrollment, verification, QR-based authentication, officer lookups, and partner integrations while giving citizens control over their identity information.

## Mission

BonID was created to help address identity verification challenges in Haiti by building secure digital identity infrastructure that expands access to services, reduces fraud, and increases trust between citizens and institutions.

## Key Features

### Citizen Portal

* OTP-based authentication
* Identity application workflow
* Document uploads
* Verification tracking
* Digital BonID profile
* Secure QR verification

### Partner Portal

* Partner onboarding
* Officer management
* Identity verification tools
* Scan history
* Verification reports

### Officer Portal (IDPol)

* QR code scanning
* BonID lookup
* Incident reporting
* Identity verification
* Scan audit logs

### Administrative Portal

* Submission review
* Identity approvals
* Partner management
* Officer invitations
* Verification analytics

## Technology Stack

### Backend

* Ruby 3.3+
* Ruby on Rails 8
* PostgreSQL

### Frontend

* Hotwire (Turbo + Stimulus)
* Bootstrap 5
* SCSS

### Authentication

* Devise
* Devise Invitable
* OTP Verification

### Infrastructure

* AWS
* Active Storage
* PostgreSQL

### Libraries

* RQRCode
* Geocoder
* Kaminari
* Wicked PDF
* Simple Form

## Installation

Clone the repository:

```bash
git clone https://github.com/YOUR_USERNAME/bonid.git
cd bonid
```

Install dependencies:

```bash
bundle install
yarn install
```

Setup database:

```bash
rails db:create
rails db:migrate
rails db:seed
```

Start development server:

```bash
bin/dev
```

Visit:

```text
http://localhost:3000
```

## Core Models

* User
* IdentitySubmission
* Partner
* PartnerApplication
* Officer
* QrScan
* QrScanLog
* IncidentReport

## Verification Workflow

1. Citizen creates account
2. Citizen submits identity documents
3. Administrator reviews application
4. Verification is approved
5. BonID is generated
6. QR code is issued
7. Identity can be verified by approved partners and officers

## Security

* Role-based access control
* Signed QR verification
* Secure verification tokens
* Audit logging
* Encrypted credentials
* Privacy-preserving identity workflows

## Roadmap

### Current

* Identity verification
* Partner onboarding
* Officer portal
* QR authentication

### Future

* Mobile applications
* Digital credentials
* Cross-border verification
* AI-assisted verification workflows
* Secure online voting research

## License

Copyright © BonID.
All rights reserved.
