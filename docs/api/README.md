# BonID Partner API Documentation

## Overview

The BonID Partner API provides verified partners (embassies, consulates, government agencies, healthcare providers) with secure access to identity verification and crime status information for Haitian citizens (BonID holders) and tourists (BonTouris holders).

## Table of Contents

- [Getting Started](#getting-started)
- [Authentication](#authentication)
- [Available APIs](#available-apis)
- [Quick Start Guide](#quick-start-guide)
- [Error Handling](#error-handling)
- [Rate Limits](#rate-limits)
- [SDKs & Libraries](#sdks--libraries)

---

## Getting Started

### 1. Register as a Partner

1. Visit `https://bonid.ht/partners/new`
2. Complete the registration form with your organization details
3. Submit required documentation for verification
4. Wait for approval (typically 2-5 business days)

### 2. Obtain API Credentials

Once approved, you'll receive:
- **API Key**: Used for all API requests (`X-Partner-Api-Key` header)
- **OAuth Client ID**: For citizen consent flows
- **OAuth Client Secret**: For token exchange

### 3. Request API Scopes

Contact BonID support to request the scopes your application needs:

| Scope | Description |
|-------|-------------|
| `openid` | Basic authentication |
| `profile` | Access to citizen profile data |
| `verifications:verify_identity` | Verify citizen identity |
| `crime:status` | Check crime involvement status |
| `crime:reports` | Search incident reports |
| `crime:certificate` | Generate crime certificates |
| `crime:full` | Full access to detailed crime records |

---

## Authentication

All API requests require **dual authentication**:

### Headers Required

```http
X-Partner-Api-Key: your_api_key_here
Authorization: Bearer your_oauth_token_here
Accept: application/json
```

### Obtaining an OAuth Token

```bash
curl -X POST 'https://bonid.ht/api/v1/oauth/token' \
  -H 'Content-Type: application/json' \
  -d '{
    "grant_type": "client_credentials",
    "client_id": "YOUR_CLIENT_ID",
    "client_secret": "YOUR_CLIENT_SECRET",
    "scope": "crime:status crime:reports crime:certificate"
  }'
```

**Response:**
```json
{
  "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "token_type": "Bearer",
  "expires_in": 3600,
  "scope": "crime:status crime:reports crime:certificate"
}
```

---

## Available APIs

### 1. Crime Status API

Check crime involvement status and retrieve incident reports.

| Endpoint | Method | Scope Required | Description |
|----------|--------|----------------|-------------|
| `/api/v1/crime_status/:bonid` | GET | `crime:status` | Check crime involvement |
| `/api/v1/incident_reports` | GET | `crime:reports` | Search reports by BonID |
| `/api/v1/incident_reports/:id/certificate` | GET | `crime:certificate` | Get official certificate |

📖 **Full Documentation:** [CRIME_STATUS_API.md](./CRIME_STATUS_API.md)

### 2. Identity Verification API

Verify citizen identity using BonID.

| Endpoint | Method | Scope Required | Description |
|----------|--------|----------------|-------------|
| `/api/v1/verify_identity` | POST | `verifications:verify_identity` | Verify identity |
| `/api/v1/bonid_status` | GET | `profile` | Get BonID status |

### 3. Consent API

Manage citizen consent for data access.

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/v1/request_consent` | POST | Request citizen consent |
| `/api/v1/citizen/approve_consent` | GET/POST | Citizen consent approval page |

---

## Quick Start Guide

### Testing Locally (Development)

Generate test credentials using the rake task:

```bash
bundle exec rails crime_api:generate_test_credentials
```

This outputs:
- Test API Key
- Test OAuth Token (24h validity)
- Sample BonIDs to test with
- Ready-to-use cURL commands

### Example: Check Crime Status

```bash
# Using the generated credentials
curl -X GET 'http://localhost:3000/api/v1/crime_status/JM-1968-M-OUEST-P2334-217' \
  -H 'X-Partner-Api-Key: bonid_live_test_xxxxx' \
  -H 'Authorization: Bearer your_token_here' \
  -H 'Accept: application/json'
```

**Response (Tier 2 - Summary):**
```json
{
  "status": "success",
  "bonid": "JM-1968-M-OUEST-P2334-217",
  "crime_status": {
    "has_criminal_record": true,
    "person_type": "citizen",
    "highest_severity_level": 4,
    "severity_label": "High",
    "is_suspect_in_any": true,
    "active_warrants": false,
    "involvement_count": 3,
    "role_breakdown": {
      "Suspect": 2,
      "Witness": 1
    }
  },
  "partner": "US Embassy Haiti",
  "access_tier": "tier_2",
  "timestamp": "2026-02-16T12:30:00Z"
}
```

### Example: Search Incident Reports

```bash
curl -X GET 'http://localhost:3000/api/v1/incident_reports?bonid=JM-1968-M-OUEST-P2334-217&role=suspect' \
  -H 'X-Partner-Api-Key: bonid_live_test_xxxxx' \
  -H 'Authorization: Bearer your_token_here' \
  -H 'Accept: application/json'
```

### Example: Get Certificate (JSON)

```bash
curl -X GET 'http://localhost:3000/api/v1/incident_reports/UUID_HERE/certificate' \
  -H 'X-Partner-Api-Key: bonid_live_test_xxxxx' \
  -H 'Authorization: Bearer your_token_here' \
  -H 'Accept: application/json'
```

### Example: Get Certificate (PDF)

```bash
curl -X GET 'http://localhost:3000/api/v1/incident_reports/UUID_HERE/certificate?format=pdf' \
  -H 'X-Partner-Api-Key: bonid_live_test_xxxxx' \
  -H 'Authorization: Bearer your_token_here' \
  -H 'Accept: application/pdf' \
  -o certificate.pdf
```

---

## BonID Formats

### Citizens (BonID)
Format: `INITIALS-YEAR-SEX-DEPARTMENT-P-UNIQUE_ID`

Example: `JM-1968-M-OUEST-P2334-217`

- `JM` - Initials
- `1968` - Birth year
- `M` - Sex (M/F/X)
- `OUEST` - Department
- `P` - Prefix
- `2334-217` - Unique identifier (7 digits)

### Tourists (BonTouris)
Format: `T-INITIALS-YEAR-SEX-COUNTRY-P-PASSPORT_DIGITS`

Example: `T-JS-1990-M-US-P-988455`

- `T` - Tourist prefix
- `JS` - Initials
- `1990` - Birth year
- `M` - Sex
- `US` - Country code
- `P` - Prefix
- `988455` - Last 6 digits of passport

### Simplified Lookup (6 digits)
For convenience, you can also search using just the last 6 digits:

```bash
curl -X GET 'http://localhost:3000/api/v1/crime_status/234217' \
  -H 'X-Partner-Api-Key: ...' \
  -H 'Authorization: Bearer ...'
```

---

## Access Tiers

The Crime Status API provides tiered access based on your partner type and scopes:

| Tier | Access Level | Who Gets This |
|------|--------------|---------------|
| **Tier 1** | Basic (yes/no + severity) | All partners with `crime:status` |
| **Tier 2** | Summary (counts, roles, dates) | Embassy/Government partners |
| **Tier 3** | Full details + incidents | Embassy/Government + `crime:full` scope |

### Tier 1 Response Fields
- `has_criminal_record` (boolean)
- `highest_severity_level` (1-6)
- `is_suspect_in_any` (boolean)
- `active_warrants` (boolean)

### Tier 2 Additional Fields
- `involvement_count`
- `role_breakdown`
- `crime_types`
- `earliest_incident` / `latest_incident`
- `severity_distribution`

### Tier 3 Additional Fields
- `incidents` (full incident list with details)
- `timeline`
- `risk_assessment`

---

## Error Handling

### HTTP Status Codes

| Code | Meaning |
|------|---------|
| 200 | Success |
| 400 | Bad Request - Invalid parameters |
| 401 | Unauthorized - Invalid credentials |
| 403 | Forbidden - Insufficient scope or consent required |
| 404 | Not Found - BonID not found |
| 429 | Too Many Requests - Rate limit exceeded |
| 500 | Internal Server Error |

### Error Response Format

```json
{
  "status": "error",
  "error": "Description of the error",
  "code": 400,
  "endpoint": "/api/v1/crime_status/INVALID",
  "timestamp": "2026-02-16T12:30:00Z"
}
```

### Consent Required Response

When citizen consent is needed:

```json
{
  "status": "consent_required",
  "error": "Citizen consent required for accessing this data",
  "code": 403,
  "consent_url": "https://bonid.ht/api/v1/request_consent?bonid=...",
  "timestamp": "2026-02-16T12:30:00Z"
}
```

---

## Rate Limits

| Endpoint | Limit | Window |
|----------|-------|--------|
| `/crime_status/:bonid` | 50 requests | 15 minutes |
| `/incident_reports` | 30 requests | 15 minutes |
| `/incident_reports/:id/certificate` | 30 requests | 15 minutes |

### Rate Limit Headers

Every response includes:

```http
X-RateLimit-Limit: 50
X-RateLimit-Remaining: 45
X-RateLimit-Reset: 2026-02-16T12:45:00Z
```

### Handling Rate Limits

```json
{
  "status": "rate_limited",
  "error": "Rate limit exceeded. Try again in 15 minutes.",
  "code": 429,
  "retry_after": 900
}
```

---

## Response Signing

All responses are signed using HMAC-SHA256 for integrity verification.

### Signature Headers

```http
X-Signature: 3a7f8c9d2e1b4a6f5c8d9e0a1b2c3d4e...
X-Timestamp: 2026-02-16T12:30:00Z
```

### Verifying Signatures

```ruby
# Ruby example
require 'openssl'

secret = your_api_key_digest
timestamp = response.headers['X-Timestamp']
body = response.body

expected = OpenSSL::HMAC.hexdigest('SHA256', secret, "#{timestamp}:#{body}")
actual = response.headers['X-Signature']

if ActiveSupport::SecurityUtils.secure_compare(expected, actual)
  puts "Response is authentic"
else
  puts "WARNING: Response may have been tampered with"
end
```

---

## SDKs & Libraries

### Ruby

```ruby
# Gemfile
gem 'bonid-api-client'

# Usage
client = BonID::Client.new(
  api_key: ENV['BONID_API_KEY'],
  oauth_token: ENV['BONID_OAUTH_TOKEN']
)

# Check crime status
result = client.crime_status('JM-1968-M-OUEST-P2334-217')
puts result.has_criminal_record?
```

### JavaScript/Node.js

```javascript
const BonID = require('bonid-api');

const client = new BonID({
  apiKey: process.env.BONID_API_KEY,
  oauthToken: process.env.BONID_OAUTH_TOKEN
});

// Check crime status
const result = await client.crimeStatus('JM-1968-M-OUEST-P2334-217');
console.log(result.hasCriminalRecord);
```

### Python

```python
from bonid import BonIDClient

client = BonIDClient(
    api_key=os.environ['BONID_API_KEY'],
    oauth_token=os.environ['BONID_OAUTH_TOKEN']
)

# Check crime status
result = client.crime_status('JM-1968-M-OUEST-P2334-217')
print(result['has_criminal_record'])
```

---

## Support

- **Email:** api-support@bonid.ht
- **Documentation:** https://docs.bonid.ht
- **Status Page:** https://status.bonid.ht

---

## Changelog

| Version | Date | Changes |
|---------|------|---------|
| 1.3.0 | 2026-02-16 | Added Crime Status API |
| 1.2.0 | 2026-01-15 | Added OAuth 2.0 support |
| 1.1.0 | 2025-12-01 | Added rate limiting |
| 1.0.0 | 2025-10-01 | Initial release |
