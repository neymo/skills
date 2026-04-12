---
name: reseller-api
description: >-
  Use when building a domain reseller platform, integrating the Unstoppable
  Domains partner API, white-label domain registration, programmatic domain
  management for resellers, or implementing domain search and registration for
  end users via REST API.
---

# Reseller API

The Reseller API provides domain search, registration, DNS management, and lifecycle operations for resellers offering DNS domain registration to their end users.

## Getting Started

1. Create an account on the [Reseller Dashboard](https://unstoppabledomains.com/reseller-dashboard)
2. Obtain your API key from the dashboard
3. Use as Bearer token: `Authorization: Bearer YOUR_API_KEY`

## Environments

| Environment | Base URL |
|---|---|
| Production | `https://api.unstoppabledomains.com/partner/v3` |
| Sandbox | `https://api.ud-sandbox.com/partner/v3` |

No charge for sandbox usage.

## Your First Request

```bash
curl "https://api.ud-sandbox.com/partner/v3/domains?query=example.com&ending=com&\$expand=registration" \
  -H "Authorization: Bearer YOUR_API_KEY"
```

## Core Concepts

**Operations** — Every mutating call returns an Operation object: `QUEUED -> PROCESSING -> COMPLETED | FAILED | CANCELLED`. Poll `GET /operations/{id}` to track progress. Use webhooks in production instead of polling.

**Preview Mode** — Add `$preview=true` to validate requests and get price quotes without executing. No charges incurred.

**Domain Flags** — 6 flags control domain behavior: `DNS_RESOLUTION`, `DNS_TRANSFER_OUT`, `DNS_DELETE`, `DNS_UPDATE`, `DNS_RENEW`, `DNS_WHOIS_PROXY`.

## Your Responsibilities

- **Domain-to-user mapping** — API does not track end-user ownership
- **Contact management** — Create/verify ICANN contacts, associate with domains
- **Payment processing** — UD invoices you; you bill your end users
- **Renewal tracking** — Monitor expiration dates, initiate renewals on time
- **DNS configuration** — Set up records on behalf of users or expose in your UI

## Key Endpoints

| Operation | Method | Path |
|---|---|---|
| Search domains | GET | `/domains?query=...&ending=...&$expand=registration` |
| Get pricing | GET | `/pricing/dns/domains/{name}` |
| Register domain | POST | `/domains?$preview=false` |
| Transfer in | POST | `/domains` (with `dns.authorizationCode`) |
| Create contact | POST | `/contacts` |
| List DNS records | GET | `/domains/{name}/dns/records` |
| Create DNS record | POST | `/domains/{name}/dns/records` |
| Set nameservers | PUT | `/domains/{name}/dns/nameservers` |
| Renew domain | POST | `/domains/{name}/renewals` |
| Get auth code | GET | `/domains/{name}/dns/authorization-code` |
| Manage flags | GET/PUT | `/domains/{name}/flags` |
| Browse marketplace | GET | `/marketplace/domains/listings?tlds=...` |
| Register webhook | POST | `/account/webhooks` |
| Check operation | GET | `/operations/{id}` |

## Documentation

- **Quick Start:** https://docs.unstoppabledomains.com/apis/reseller/quick-start
- **Implementation Guide:** https://docs.unstoppabledomains.com/apis/reseller/implementation-guide
- **API Reference (OpenAPI):** https://docs.unstoppabledomains.com/apis/reseller/openapi
- **Contact:** partnerengineering@unstoppabledomains.com

For detailed implementation guide with code examples, see [implementation.md](implementation.md).
