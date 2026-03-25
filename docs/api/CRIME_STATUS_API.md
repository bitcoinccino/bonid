# Crime Status API Documentation

## Overview

The Crime Status API allows verified partners (embassies, consulates, government agencies) to check crime involvement status and retrieve incident reports for BonID and BonTouris holders.

## Authentication

All endpoints require **dual authentication**:

1. **API Key Header**: `X-Partner-Api-Key: <your_api_key>`
2. **OAuth Bearer Token**: `Authorization: Bearer <access_token>`

### Obtaining Credentials

1. Register as a partner at `https://bonid.ht/partners/new`
2. Complete verification process
3. Request Crime API scopes during OAuth authorization

### Required OAuth Scopes

| Scope | Description |
|-------|-------------|
| `crime:status` | Check crime involvement status |
| `crime:reports` | Search and list incident reports |
| `crime:certificate` | Generate official crime certificates |
| `crime:full` | Full access to detailed records (Tier 3) |

---

## Endpoints

### 1. Check Crime Status

Check if a person has any crime involvement records.

```
GET /api/v1/crime_status/:bonid
```

#### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `bonid` | string | Yes | BonID or BonTouris number |

#### BonID Formats

- **Citizen (BonID)**: `JM-1968-M-OUEST-P2334-217`
- **Tourist (BonTouris)**: `T-JS-1990-M-US-P-988455`
- **6-digit suffix**: `234217` (simplified lookup)

#### Response (Tier 1 - Basic)

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
    "checked_at": "2026-02-16T12:30:00Z"
  },
  "partner": "US Embassy Haiti",
  "access_tier": "tier_1",
  "timestamp": "2026-02-16T12:30:00Z",
  "api_version": "1.0.0"
}
```

#### Response (Tier 2 - Summary)

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
    },
    "suspect_statuses": {
      "in_custody": 1,
      "released_on_bail": 1
    },
    "earliest_incident": "2024-03-15T00:00:00Z",
    "latest_incident": "2026-01-20T00:00:00Z",
    "crime_types": {
      "Armed Robbery": 2,
      "Theft": 1
    },
    "severity_distribution": {
      "High": 2,
      "Moderate": 1
    },
    "checked_at": "2026-02-16T12:30:00Z"
  },
  "partner": "US Embassy Haiti",
  "access_tier": "tier_2",
  "timestamp": "2026-02-16T12:30:00Z",
  "api_version": "1.0.0"
}
```

#### Response (Tier 3 - Full Details)

Tier 3 access includes all Tier 2 data plus:

```json
{
  "crime_status": {
    "...": "tier_2_fields",
    "incidents": [
      {
        "id": "abc123-uuid",
        "report_id": "PNH-CRIM-AROB-20260115-A1B2C3-XYZ",
        "case_number": "BON-CASE-2026-A1B2C3",
        "crime_type": "Armed Robbery",
        "crime_code": "AROB",
        "severity": 4,
        "severity_label": "High",
        "occurred_at": "2026-01-15T14:30:00Z",
        "submitted_at": "2026-01-15T16:00:00Z",
        "report_status": "approved",
        "involvement": {
          "role": "suspect",
          "role_label": "Suspect",
          "status": "in_custody",
          "status_label": "In Custody"
        },
        "location": {
          "commune": "Port-au-Prince",
          "department": "Ouest"
        },
        "penal_code": "Article 254-256"
      }
    ],
    "timeline": [
      {
        "date": "2026-01-15",
        "event": "Suspect in Armed Robbery",
        "status": "in_custody",
        "severity": 4
      }
    ],
    "risk_assessment": {
      "risk_level": "elevated",
      "score": 55,
      "factors": {
        "incident_count": 2,
        "max_severity": 4,
        "has_active_warrant": false,
        "is_armed_or_dangerous": false
      }
    }
  }
}
```

---

### 2. Search Incident Reports

Search for incident reports involving a specific BonID holder.

```
GET /api/v1/incident_reports?bonid=JM-1968-M-OUEST-P2334-217
```

#### Query Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `bonid` | string | Yes | BonID or BonTouris number |
| `role` | string | No | Filter by role: `suspect`, `victim`, `witness`, `innocent`, `accomplice` |
| `status` | string | No | Filter by involvement status |
| `from_date` | string | No | Filter from date (ISO8601) |
| `to_date` | string | No | Filter to date (ISO8601) |
| `page` | integer | No | Page number (default: 1) |
| `per_page` | integer | No | Results per page (default: 20, max: 50) |

#### Response

```json
{
  "status": "success",
  "bonid": "JM-1968-M-OUEST-P2334-217",
  "reports": [
    {
      "id": "abc123-uuid",
      "report_id": "PNH-CRIM-AROB-20260115-A1B2C3-XYZ",
      "case_number": "BON-CASE-2026-A1B2C3",
      "crime_type": "Armed Robbery",
      "crime_code": "AROB",
      "severity": 4,
      "occurred_at": "2026-01-15T14:30:00Z",
      "submitted_at": "2026-01-15T16:00:00Z",
      "status": "approved",
      "involvement": {
        "role": "suspect",
        "status": "in_custody"
      },
      "location": {
        "commune": "Port-au-Prince",
        "department": "Ouest"
      }
    }
  ],
  "pagination": {
    "page": 1,
    "per_page": 20,
    "total_count": 3,
    "total_pages": 1
  },
  "partner": "US Embassy Haiti",
  "timestamp": "2026-02-16T12:30:00Z",
  "api_version": "1.0.0"
}
```

---

### 3. Get Incident Certificate

Retrieve an official crime certificate for a specific incident report.

```
GET /api/v1/incident_reports/:id/certificate
```

#### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `id` | string | Yes | Incident report UUID |
| `format` | string | No | Response format: `json` (default) or `pdf` |

#### JSON Response

```json
{
  "status": "success",
  "certificate": {
    "certificate_id": "CERT-PNH-CRIM-AROB-20260115-A1B2C3-XYZ-20260216123000",
    "type": "CRIME_INCIDENT_CERTIFICATE",
    "version": "1.0.0",
    "issued_at": "2026-02-16T12:30:00Z",
    "valid_until": "2026-02-17T12:30:00Z",
    "issuing_authority": {
      "name": "Police Nationale d'Haïti",
      "abbreviation": "PNH",
      "country": "Haiti"
    },
    "incident": {
      "report_id": "PNH-CRIM-AROB-20260115-A1B2C3-XYZ",
      "case_number": "BON-CASE-2026-A1B2C3",
      "crime_type": "Armed Robbery",
      "severity": {
        "level": 4,
        "label": "Élevé"
      },
      "occurred_at": "2026-01-15T14:30:00Z",
      "description": "Armed robbery at commercial establishment..."
    },
    "persons_involved": [
      {
        "role": "suspect",
        "role_label": "Suspect",
        "status": "in_custody",
        "id_type": "BonID",
        "masked_id": "JM-••••-•-•••••-P2334-217"
      }
    ],
    "location": {
      "commune": "Port-au-Prince",
      "department": "Ouest",
      "country": "Haiti"
    },
    "legal_references": {
      "penal_code_articles": "Article 254-256",
      "jurisdiction": "Haiti National"
    },
    "verification": {
      "certificate_hash": "3a7f8c9d2e1b4a6f5c8d9e0a1b2c3d4e...",
      "verification_url": "https://bonid.ht/verify/certificate/CERT-...",
      "valid_for_hours": 24
    },
    "digital_signature": {
      "algorithm": "HMAC-SHA256",
      "signature": "...",
      "signed_at": "2026-02-16T12:30:00Z"
    }
  },
  "partner": "US Embassy Haiti",
  "generated_at": "2026-02-16T12:30:00Z",
  "valid_until": "2026-02-17T12:30:00Z",
  "api_version": "1.0.0"
}
```

#### PDF Response

When `format=pdf` or `Accept: application/pdf` header is set:

- Content-Type: `application/pdf`
- Content-Disposition: `attachment; filename="certificate-{report_id}.pdf"`
- X-Certificate-ID: Certificate ID
- X-Generated-At: Generation timestamp
- X-Valid-Until: Expiration timestamp

---

## Error Responses

### 400 Bad Request

```json
{
  "status": "error",
  "error": "Missing required 'bonid' parameter",
  "code": 400,
  "endpoint": "/api/v1/crime_status",
  "timestamp": "2026-02-16T12:30:00Z"
}
```

### 401 Unauthorized

```json
{
  "status": "unauthorized",
  "error": "Invalid or expired OAuth token",
  "code": 401,
  "timestamp": "2026-02-16T12:30:00Z"
}
```

### 403 Forbidden

```json
{
  "status": "forbidden",
  "error": "Insufficient scope. Required: crime:status",
  "code": 403,
  "timestamp": "2026-02-16T12:30:00Z"
}
```

### 403 Consent Required

```json
{
  "status": "consent_required",
  "error": "Citizen consent required for accessing this data",
  "code": 403,
  "consent_url": "https://bonid.ht/api/v1/request_consent?bonid=...",
  "timestamp": "2026-02-16T12:30:00Z"
}
```

### 404 Not Found

```json
{
  "status": "error",
  "error": "BonID not found or not verified",
  "code": 404,
  "timestamp": "2026-02-16T12:30:00Z"
}
```

### 429 Rate Limited

```json
{
  "status": "rate_limited",
  "error": "Rate limit exceeded. Try again in 15 minutes.",
  "code": 429,
  "retry_after": 900,
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

Rate limit headers are included in all responses:

- `X-RateLimit-Limit`: Maximum requests allowed
- `X-RateLimit-Remaining`: Requests remaining
- `X-RateLimit-Reset`: Reset timestamp (ISO8601)

---

## Response Headers

All responses include:

| Header | Description |
|--------|-------------|
| `X-BonID-API-Version` | API version (1.3.0) |
| `X-BonID-Environment` | Environment (production, staging) |
| `X-Signature` | HMAC-SHA256 response signature |
| `X-Timestamp` | Signature timestamp |

---

## Citizen Consent

Access to detailed crime records (Tier 3) and certificates requires citizen consent. The consent flow:

1. Partner requests data via API
2. API returns `403 consent_required` with `consent_url`
3. Partner redirects citizen to consent page
4. Citizen approves/denies access
5. Partner can now access data with valid consent

---

## Access Tiers

| Tier | Access Level | Requirements |
|------|--------------|--------------|
| Tier 1 | Basic (yes/no + severity) | `crime:status` scope |
| Tier 2 | Summary (counts, roles, dates) | Embassy/consulate partner + `crime:status` |
| Tier 3 | Full details | Embassy/consulate + `crime:full` + citizen consent |

---

## Example Usage

### cURL

```bash
curl -X GET "https://bonid.ht/api/v1/crime_status/JM-1968-M-OUEST-P2334-217" \
  -H "X-Partner-Api-Key: bonid_live_abc123..." \
  -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..." \
  -H "Accept: application/json"
```

### Ruby

```ruby
require 'net/http'
require 'json'

uri = URI('https://bonid.ht/api/v1/crime_status/JM-1968-M-OUEST-P2334-217')

request = Net::HTTP::Get.new(uri)
request['X-Partner-Api-Key'] = 'bonid_live_abc123...'
request['Authorization'] = 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...'
request['Accept'] = 'application/json'

response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
  http.request(request)
end

data = JSON.parse(response.body)
puts data['crime_status']['has_criminal_record']
```

### JavaScript

```javascript
const response = await fetch(
  'https://bonid.ht/api/v1/crime_status/JM-1968-M-OUEST-P2334-217',
  {
    headers: {
      'X-Partner-Api-Key': 'bonid_live_abc123...',
      'Authorization': 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...',
      'Accept': 'application/json'
    }
  }
);

const data = await response.json();
console.log(data.crime_status.has_criminal_record);
```

---

## Support

For API support, contact: api-support@bonid.ht

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2026-02-16 | Initial release |
