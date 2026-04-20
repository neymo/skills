---
name: domains
description: >-
  Use when searching for domains, checking availability, buying or registering
  domains, configuring DNS records, managing a domain portfolio, listing domains
  for sale, responding to offers, contacting sellers, generating AI landing
  pages, backordering expiring domains, renewing domains, or troubleshooting
  Unstoppable Domains MCP/CLI/API errors.
---

# Unstoppable Domains — User API

Complete reference for the Unstoppable Domains User API via MCP server, CLI, or REST API. For the full tool catalog with descriptions, see [tools-full.md](tools-full.md).

## General Notes

- All prices in **cents USD** (e.g., `5000` = $50.00)
- All timestamps in **UTC (ISO 8601)** — convert to user's local timezone for display
- Magic link URLs (from `ud_cart_get_url`, `ud_cart_add_payment_method_url`, `ud_authenticated_url_get`, `signatureNote` fields) are **single-use, valid 60 seconds**
- Most bulk operations: **max 50 per call**
- 12 tools support `applyToAllDomainsInPortfolio: true` for portfolio-wide operations
- Domain names are **case-insensitive** (API normalizes to lowercase)

---

## Search & Purchase

`ud_domains_search` accepts up to **10 queries** and **5 TLDs** per call (defaults: com, net, org, ai, io). `ud_tld_list` shows all supported TLDs. For pending-delete/expiring inventory, use `ud_expireds_list` (up to 500/call).

### Domain Naming Principles

When suggesting domain names to a user, apply these rules to every candidate:

**Hard blockers (never propose these):**

- **No hyphens** — single-dash (`brew-haven.com`), multi-dash (`the-best-coffee-shop.com`), trailing or leading dash. Hyphens signal low quality and hurt type-in recall.
- **No digits** — no digit substitution (`4you`, `2fast`), no suffix numbers (`coffee24`, `domain365`), no leet (`c0ffee`). Digit names read as spammy and date the brand.
- **No trademark-adjacent names** — avoid names one letter off a well-known brand (`gooogle`, `amaz0n`), even if technically available. Registrar support will field takedown complaints.
- If the only available candidate is hyphenated, numeric, or trademark-adjacent, discard it. Re-run the search with a different seed or TLD.

**Quality guidelines:**

- **Length**: prefer 3–12 characters in the SLD (second-level domain). Sub-15 is passable; longer loses memorability.
- **Pronounceability**: should be sayable in a single beat. Test: can you spell it to a stranger over a phone call?
- **Brandability over description**: prefer invented-but-pronounceable (`brewhaven`) or meaningful compounds (`cozycoffee`) over literal descriptions (`coffeeshopportland`). Descriptive names don't scale with the brand.
- **TLD coherence**: match TLD to pitch. `.store` for e-commerce, `.io` for tech, `.design` for studios. A `.biz` on a tech startup reads as low quality.

Good examples: `brewhaven.com`, `cozycoffee.co`, `roasted.studio`. Bad examples: `brew-haven.com`, `brew2haven.com`, `coffeeshopindowntownportland.com`.

### Cart Tool Selection (Critical)

After searching, use `marketplace.source` and `marketplace.status` to pick the correct cart tool:

| source | status | Action |
|---|---|---|
| `unstoppable_domains` | `available` | `ud_cart_add_domain_registration` |
| `unstoppable_domains` | `registered-listed-for-sale` | `ud_cart_add_domain_listed` |
| `unstoppable_domains` | `registered-listed-for-offers` | Cannot cart. Share `purchaseUrl` for offers. |
| `afternic` | `registered-listed-for-sale` | `ud_cart_add_domain_afternic` |
| `sedo` | `registered-listed-for-sale` | `ud_cart_add_domain_sedo` |
| any | `registered-not-for-sale` | Not purchasable. Use `ud_lead_get` to contact seller. |

**Using the wrong cart tool will fail.** Always check `marketplace.source` first.

### Registration Workflow

DNS domains (.com, .org, .net, etc.) require an ICANN contact before checkout.

```
1. ud_domains_search              -> Find available domains
2. ud_contacts_list               -> Check for existing ICANN contacts
3. ud_contact_create              -> Create if none (suggest account email for instant verification)
4. ud_cart_add_domain_registration -> Add to cart (max 50 domains)
5. ud_cart_get_payment_methods    -> Verify payment method or sufficient credits
6. ud_cart_checkout               -> Complete purchase (pass paymentMethodId if credits insufficient)
```

**Draft contacts** (ID starts with `draft-`) are still syncing. Wait a few seconds and re-check `ud_contacts_list`.

### Marketplace Purchase

```
1. ud_domains_search          -> Note marketplace.source and marketplace.status
2. Correct cart tool          -> See table above
3. ud_cart_get                -> Verify cart contents and pricing
4. ud_cart_get_payment_methods -> Check payment
5. ud_cart_checkout           -> Or ud_cart_get_url for browser checkout
```

### Lease-to-Own

Only UD marketplace listings support LTO. Check search results for `listingSettings.leaseToOwnOptions`:

- `type`: `equal_installments` or `down_payment_plus_equal_installments`
- `termLength`: 2-120 months (must not exceed `maxTermLength`)
- `downPaymentPercentage`: 10-90% (only for down_payment type)

Pass `leaseToOwnOptions` to `ud_cart_add_domain_listed`.

### Backorders

For pending-delete/coming-soon domains:

```
1. ud_expireds_list or ud_domains_search -> Find domain + availability timestamp
2. ud_contacts_list / ud_contact_create  -> Ensure ICANN contact exists
3. ud_backorder_create                   -> Place backorder (needs contactId + availableAfterTimestamp)
```

Registration fee charged only on successful catch. Domainer Club members get up to $500 overdraft. Others must prepay at `unstoppabledomains.com/account-prepay`. Manage with `ud_backorders_list` and `ud_backorder_cancel`.

### Cart Tools

| Tool | Purpose |
|---|---|
| `ud_cart_get` | View cart with pricing breakdown |
| `ud_cart_remove` | Remove items from cart |
| `ud_cart_get_url` | Magic link for browser checkout (60s, single-use) |
| `ud_cart_add_payment_method_url` | Magic link to add payment method |
| `ud_cart_add_domain_renewal` | Add renewals (1-10 years, max 50 domains) |
| `ud_cart_add_ai_credits` | Add AI credit packs |

---

## DNS Management

**Always check nameservers first.** DNS record management only works with UD default nameservers.

```
1. ud_dns_nameservers_list     -> Check nameserver status
2. ud_dns_records_list         -> View current records
3. ud_dns_record_add           -> Add records (upsert modes: append, replace, disallowed)
4. ud_domain_pending_operations -> Verify changes (DNS changes are async)
```

Record types: A, AAAA, CNAME, MX, TXT, NS, SRV, CAA. TTL: 60-86400 (default: 3600).

`ud_dns_record_update` updates by record ID. `ud_dns_record_remove` deletes by record ID. `ud_dns_records_remove_all` requires `confirmDeleteAll: true` — destructive.

### Common DNS Recipes

**Google Workspace email:** MX records at root (`@`): `1 aspmx.l.google.com.`, `5 alt1.aspmx.l.google.com.`, `5 alt2.aspmx.l.google.com.`, `10 alt3.aspmx.l.google.com.`, `10 alt4.aspmx.l.google.com.` + TXT: `v=spf1 include:_spf.google.com ~all`

**Point to web server:** A record at `@` with server IP, plus CNAME `www` -> `example.com.`

### Nameservers

- `ud_dns_nameservers_set_custom` — 2-12 hostnames. **Disables** DNS record management.
- `ud_dns_nameservers_set_default` — **Re-enables** record management. External records do NOT carry over.

### Hosting & Forwarding

- `ud_dns_hosting_add` — `LISTING_PAGE` (for-sale page), `REDIRECT_301`, `REDIRECT_302`. `forceCompatibility: true` auto-switches nameservers.
- `ud_dns_hosting_list` / `ud_dns_hosting_remove` — view/remove configs.

### DNS Presets

`ud_presets_list`, `ud_presets_save`, `ud_presets_apply`, `ud_presets_delete` — reusable nameserver, record, and forwarding configs.

---

## Portfolio Management

`ud_portfolio_list` for portfolio-wide scans/stats. Filters: `searchTerm`, `status`, `expiringWithinDays`, `expired`, `minLength`, `maxLength`, `autoRenewal`, `tagFilters`. Sorting by name/length/purchasedAt/expiresAt/listingPrice/offers/leads/watchlistCount. `pageSize` up to 500.

`ud_domain_get` for deep inspection of up to 50 named domains — lifecycle, flags, DNS, marketplace metrics, tags, pending operations.

### Renewals

```
1. ud_portfolio_list           -> Check expiration dates
2. ud_cart_add_domain_renewal  -> Add renewals (1-10 years, max 50)
3. ud_cart_get_payment_methods -> Verify payment
4. ud_cart_checkout            -> Complete
```

### Auto-Renewal

`ud_domain_auto_renewal_update` — enable/disable. Needs valid payment method on file.

### Tags & Flags

- `ud_domain_tags_add` / `ud_domain_tags_remove` — max 10 tags/call, 20 chars each. Auto-creates. Idempotent.
- `ud_domain_flags_update` — WHOIS privacy (`DNS_WHOIS_PROXY`: ENABLED recommended), transfer lock (`DNS_TRANSFER_OUT`: DISABLED = locked, recommended).

### Domain Transfer (Push)

`ud_domain_push` — requires `targetAccountId` (format: `adjective-noun-xxx`), `otpCode` (6-digit MFA). Max 50 domains. Recipient accepts within 4 hours. User must have MFA enabled.

### Portfolio-Wide Operations

12 tools support `applyToAllDomainsInPortfolio: true`, bypassing the 50-domain limit: `generate_lander`, `remove_lander`, `tags_add`, `tags_remove`, `flags_update`, `auto_renewal_update`, `hosting_add`, `hosting_remove`, `nameservers_set_default`, `nameservers_set_custom`, `records_remove_all`, `record_add`.

---

## Marketplace & Offers

### Listing Domains for Sale

```
1. ud_portfolio_list   -> Confirm ownership
2. ud_listing_create   -> Create listing (price, offers, validity, LTO)
3. ud_offers_list      -> Monitor incoming offers
4. ud_offer_respond    -> Accept or reject
```

Listing settings: `priceInCents` ($11-$2M, `0` = offers-only), `expiresAt` (default 90 days), `isOfferFeatureEnabled`, `minOfferAmountInCents`, `isEmailAliasUsed`, `leaseToOwnOptions`. `ud_listing_update` / `ud_listing_cancel` support bulk (max 50). Listings may require signing — `signatureNote` URLs are magic links.

### Offers

- `ud_offers_list` — filter by `domainName`, `group` (active/sold)
- `ud_offer_respond` — accept/reject, up to 50. Acceptance may require signing.
- Counter-offers: use conversations to message buyer with counter price.

### Buyer-Seller Conversations

`ud_leads_list` (filter by domain), `ud_lead_get` (get or create), `ud_lead_messages_list` (newest-first, cursor pagination), `ud_lead_message_send` (max 1000 chars). Display messages in chronological order.

---

## AI Landing Pages

Each generation costs **1 AI credit**. New accounts get 5 free. `ud_ai_credits_get` checks balance. `ud_cart_add_ai_credits` to purchase more.

- `ud_domain_generate_lander` — async, custom instructions (tone/colors/content), max 50, supports `applyToAllDomainsInPortfolio`
- `ud_domain_lander_status` — pending/generating/processing/hosted/failed/none
- `ud_domain_download_lander` — `htmlContent` (single-page) or `zipContent` (base64 multi-file)
- `ud_domain_upload_lander` — HTML or zip, **requires Domainer Club**, max 1MB, replaces existing
- `ud_domain_remove_lander` — **destructive**, supports `applyToAllDomainsInPortfolio`

---

## Troubleshooting

### Cart Add Failures

| Error | Fix |
|---|---|
| "Expected a domain" / cart tool mismatch | Check `marketplace.source` from search results. Use matching cart tool. |
| Domain not available | Re-run `ud_domains_search`. Suggest alternatives. |

### Checkout Failures

| Error | Fix |
|---|---|
| Missing ICANN contact | `ud_contacts_list` then `ud_contact_create`. Use account email for instant verification. |
| Contact in draft (`draft-*` ID) | Wait a few seconds, re-check `ud_contacts_list`. |
| No payment method / insufficient balance | `ud_cart_get_payment_methods` to check. Pass `paymentMethodId` or use `ud_cart_add_payment_method_url`. |

### DNS Issues

| Error | Fix |
|---|---|
| Cannot modify records | Domain uses custom nameservers. Switch to UD defaults or manage at external provider. |
| Changes not appearing | DNS is async. Use `ud_domain_pending_operations`. |
| Record already exists | Use `upsertMode: "append"` or `"replace"`. |
| NO_CHANGE | Domain expired or in redemption. Check `ud_domain_get`. |

### Auth / Connection

| Error | Fix |
|---|---|
| 401 Unauthorized | Re-authenticate: `ud auth login` or reconnect OAuth. |
| 403 Forbidden | Missing OAuth scope. Check Account Settings > Connected Apps. |
| MCP not connecting | Verify with `claude mcp list`. Check Desktop config file path. Restart after changes. |

### Domain Push

| Error | Fix |
|---|---|
| MFA not enabled | Must enable in account security settings first. |
| Invalid OTP | Time-based — ask for fresh code. |
| Domain ineligible | Check `ud_domain_get` — expired, pending transfer, or non-ICANN domains can't be pushed. |

### CLI Debugging

```bash
ud auth status          # Check authentication
ud --env sandbox ...    # Test in sandbox (no charges)
ud --output json ...    # Raw JSON for debugging
```
