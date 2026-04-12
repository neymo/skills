# Reseller API — Implementation Guide

Detailed implementation guide for the Unstoppable Domains Reseller API. Use after completing the [Quick Start](https://docs.unstoppabledomains.com/apis/reseller/quick-start).

## Search and Registration Flow

### Step 1: Search for Available Domains

```bash
curl "https://api.ud-sandbox.com/partner/v3/domains?query=example.com&ending=com&\$expand=registration" \
  -H "Authorization: Bearer YOUR_API_KEY"
```

Response times vary by TLD. `.com` is consistently fast; some TLDs (e.g., Identity Digital) may take over 1 second.

### Step 2: Check Pricing

```bash
curl "https://api.ud-sandbox.com/partner/v3/pricing/dns/domains/example.com" \
  -H "Authorization: Bearer YOUR_API_KEY"
```

Returns registration price, renewal price, and applicable fees.

### Step 3: Create a Contact

ICANN contacts are required before registration.

```bash
curl -X POST "https://api.ud-sandbox.com/partner/v3/contacts" \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "firstName": "Jane",
    "lastName": "Doe",
    "email": "jane.doe@example.com",
    "phone": { "dialingPrefix": "+1", "number": "5551234567" },
    "countryCode": "US",
    "street": "123 Main St",
    "city": "San Francisco",
    "postalCode": "94105",
    "stateProvince": "CA"
  }'
```

Contacts must verify their email before use. Verification progresses: `UNVERIFIED -> REQUESTED -> PENDING -> VERIFIED`. Only `VERIFIED` contacts can be used.

### Step 4: Register the Domain

Use `$preview=true` first to validate and get a price quote, then `$preview=false` to execute:

```bash
curl -X POST "https://api.ud-sandbox.com/partner/v3/domains?\$preview=false" \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "example.com",
    "owner": {
      "type": "MANAGED",
      "contact": "ct-a1b2c3d4-5678-90ab-cdef-1234567890ab"
    },
    "dns": {
      "period": 1,
      "contacts": {
        "admin": "ct-a1b2c3d4-5678-90ab-cdef-1234567890ab",
        "tech": "ct-a1b2c3d4-5678-90ab-cdef-1234567890ab",
        "billing": "ct-a1b2c3d4-5678-90ab-cdef-1234567890ab"
      }
    }
  }'
```

### Step 5: Track the Operation

```bash
curl "https://api.ud-sandbox.com/partner/v3/operations/{id}" \
  -H "Authorization: Bearer YOUR_API_KEY"
```

Poll every 2-5 seconds with a timeout. For production, use webhooks instead of polling.

## Operations

Every mutating API call returns an **Operation** object:

```
QUEUED -> PROCESSING -> COMPLETED | FAILED | CANCELLED
```

Additional statuses: `PREVIEW` (from preview mode), `AWAITING_UPDATES` (needs additional input).

Operations contain **dependencies** — smaller units of work with their own statuses for granular tracking.

## Preview Mode

Add `$preview=true` to any mutating request to validate without executing. Returns what the Operation would look like with status `PREVIEW`. No charges incurred. Useful for price quotes and parameter validation.

## Domain Flags

| Flag | Description |
|---|---|
| `DNS_RESOLUTION` | Controls DNS resolution |
| `DNS_TRANSFER_OUT` | Controls outbound transfer capability |
| `DNS_DELETE` | Controls domain deletion |
| `DNS_UPDATE` | Controls DNS record modification |
| `DNS_RENEW` | Controls renewal capability |
| `DNS_WHOIS_PROXY` | Controls WHOIS privacy protection |

Some flags may be read-only (reasons: `ADMIN`, `HOSTING`, `DNS_PROVIDER`).

```bash
# View flags
curl "https://api.ud-sandbox.com/partner/v3/domains/example.com/flags" \
  -H "Authorization: Bearer YOUR_API_KEY"

# Update flags
curl -X PUT "https://api.ud-sandbox.com/partner/v3/domains/example.com/flags" \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{ "DNS_TRANSFER_OUT": false, "DNS_WHOIS_PROXY": true }'
```

## Marketplace Listings

Browse the secondary marketplace:

```bash
curl "https://api.ud-sandbox.com/partner/v3/marketplace/domains/listings?tlds=com&perPage=10&\$page=1" \
  -H "Authorization: Bearer YOUR_API_KEY"
```

Filter by name with `q` parameter. Sort with `orderBy` (price, name, listedAt) and `orderDirection`. Paginate with `$page` (1-indexed) and `perPage` (1-100). `next` field provides next page params or `null` on last page.

## Contact Management

### Required Fields

| Field | Description |
|---|---|
| `firstName` | Contact's first name |
| `lastName` | Contact's last name |
| `email` | For verification |
| `phone` | Object: `{ dialingPrefix, number }` |
| `countryCode` | ISO 2-letter code |
| `street` | Street address |
| `city` | City |
| `postalCode` | ZIP/postal code |
| `stateProvince` | State or province |

`organization` is optional (for business registrations).

### Contact Roles

- **Owner (Registrant)** — Legal owner. Set via `owner` field.
- **Admin** — Administrative contact.
- **Tech** — Technical/DNS contact.
- **Billing** — Payment and renewal contact.

Update contacts post-registration:

```bash
curl -X PUT "https://api.ud-sandbox.com/partner/v3/domains/{name}/dns/contacts" \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{ "admin": "ct-new-id", "tech": "ct-new-id", "billing": "ct-new-id" }'
```

### Inline vs. Referenced Contacts

- **Referenced** — Create via `POST /contacts`, then use ID during registration. Good for reuse.
- **Inline** — Provide full details in registration request body. Good for one-off registrations.

## DNS Management

### Records

```bash
# List records (filter by type and subName)
curl "https://api.ud-sandbox.com/partner/v3/domains/example.com/dns/records?type=A&subName=www" \
  -H "Authorization: Bearer YOUR_API_KEY"

# Create record
curl -X POST "https://api.ud-sandbox.com/partner/v3/domains/example.com/dns/records" \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{ "type": "A", "subName": "www", "value": "192.0.2.1", "ttl": 3600 }'

# Update record (by record ID rr-<uuid>)
curl -X PUT "https://api.ud-sandbox.com/partner/v3/domains/example.com/dns/records/rr-a1b2c3d4" \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{ "value": "192.0.2.2", "ttl": 7200 }'

# Delete record
curl -X DELETE "https://api.ud-sandbox.com/partner/v3/domains/example.com/dns/records/rr-a1b2c3d4" \
  -H "Authorization: Bearer YOUR_API_KEY"
```

Supported types: A, AAAA, CNAME, MX, TXT, SRV, and others.

**Upsert modes** (`$upsert` query param):

| Value | Behavior |
|---|---|
| `REPLACE` | Replace existing record |
| `APPEND` | Add alongside existing |
| `DISALLOWED` | Fail if conflict (default) |

### Nameservers

```bash
# Set custom nameservers (2-12 required)
curl -X PUT "https://api.ud-sandbox.com/partner/v3/domains/example.com/dns/nameservers" \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{ "nameservers": ["ns1.example.net", "ns2.example.net"] }'

# Revert to UD-managed nameservers
curl -X DELETE "https://api.ud-sandbox.com/partner/v3/domains/example.com/dns/nameservers" \
  -H "Authorization: Bearer YOUR_API_KEY"
```

### Batch Updates

`PATCH /domains/{name}` modifies nameservers, DNSSEC, contacts, flags, and DNS records in a single request.

## Domain Lifecycle

### Renewal

```bash
# Check eligibility and pricing
curl "https://api.ud-sandbox.com/partner/v3/domains/example.com/renewals" \
  -H "Authorization: Bearer YOUR_API_KEY"

# Renew (period in years)
curl -X POST "https://api.ud-sandbox.com/partner/v3/domains/example.com/renewals" \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{ "period": 1 }'
```

### Transfer Out

1. Enable `DNS_TRANSFER_OUT` flag
2. Get EPP authorization code:
```bash
curl "https://api.ud-sandbox.com/partner/v3/domains/example.com/dns/authorization-code" \
  -H "Authorization: Bearer YOUR_API_KEY"
```
3. Provide code to the gaining registrar

### Transfer In

Use the same `POST /domains` endpoint. Include `dns.authorizationCode` — the presence of an auth code tells the API this is a transfer:

```bash
curl -X POST "https://api.ud-sandbox.com/partner/v3/domains?\$preview=false" \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "example.com",
    "owner": { "type": "MANAGED", "contact": "ct-..." },
    "dns": {
      "authorizationCode": "EPP_AUTH_CODE_HERE",
      "contacts": { "admin": "ct-...", "tech": "ct-...", "billing": "ct-..." }
    }
  }'
```

## Hosting

Configure how domains serve content:

| Type | Description |
|---|---|
| `REDIRECT_301` | Permanent redirect to another URL |
| `REDIRECT_302` | Temporary redirect |
| `REVERSE_PROXY` | Proxy requests to backend server |

All hosting configs require SSL certificate provisioning (`certificateStatus: PENDING` until active).

## Webhooks

### Event Types

| Type | Description |
|---|---|
| `OPERATION_FINISHED` | Operation completed (success or failure) |
| `OPERATION_ACTION_REQUIRED` | Needs manual intervention |
| `OPERATION_CREATED` | New operation started |

### Register

```bash
curl -X POST "https://api.ud-sandbox.com/partner/v3/account/webhooks" \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{ "url": "https://your-platform.com/webhooks/ud", "type": "OPERATION_FINISHED" }'
```

### Verification

Verify `x-ud-signature` header: HMAC-SHA256 of raw request body using your API key, Base64-encoded.

```javascript
const crypto = require("crypto");

function verifyWebhook(rawBody, signature, apiKey) {
  const expected = crypto
    .createHmac("sha256", apiKey)
    .update(rawBody)
    .digest("base64");
  return crypto.timingSafeEqual(
    Buffer.from(signature),
    Buffer.from(expected)
  );
}
```

### Retry Behavior

Non-200 responses trigger retries with exponential backoff: 1m, 2m, 4m, 8m, 16m, 32m, 64m, 120m (8 attempts max).

## Error Handling

| Code | Meaning |
|---|---|
| 400 | Validation error — invalid body or parameters |
| 401 | Authentication error — missing or invalid API key |
| 403 | Permission error — insufficient access |
| 404 | Not found — domain, contact, or operation doesn't exist |
| 409 | Conflict — action conflicts with current state |

**Partial failures:** Operations can have mixed dependency statuses. Always check each dependency's status individually.

## API Reference

Full endpoint details, schemas, and examples: https://docs.unstoppabledomains.com/apis/reseller/openapi
