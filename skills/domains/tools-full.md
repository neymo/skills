# Unstoppable Domains — Complete Tool Reference

All tools available via the MCP server, CLI, and API.

## Domain Search

| Tool | Description |
|---|---|
| `ud_domains_search` | Search for domain availability and pricing across TLDs. Up to 10 queries and 5 TLDs per request (defaults: com, net, org, ai, io). Returns `marketplace.source` and `marketplace.status` to determine which cart tool to use. |
| `ud_tld_list` | List all available ICANN TLDs supported by the registrar. Call before searching specific TLDs to verify support. |
| `ud_expireds_list` | Browse pending-delete / expireds marketplace. Domains spend 5 days in `COMING_SOON`, then drop to `AVAILABLE_BACKORDER`. Filter by status, TLD, label length, watchlist count, backorder count. `limit` up to 500/call. |
| `ud_knowledge_base_search` | Search the Knowledge Base for help articles by keyword. Returns articles ranked by relevance with titles, snippets, and direct links. No authentication required. |

## Portfolio Management

| Tool | Description |
|---|---|
| `ud_portfolio_list` | List domains with filtering and sorting. Use for portfolio-wide scans, rankings, aggregates. Returns per-domain `offersCount`, `leadsCount`, `watchlistCount`, listing price/status, `listing.views`. `pageSize` up to 500. |
| `ud_domain_get` | Comprehensive domain info for explicitly named domains (up to 50). Returns lifecycle (renewal, expiration, auto-renewal), flags, DNS config, marketplace metrics, tags, pending operations. |

## ICANN Contacts

| Tool | Description |
|---|---|
| `ud_contacts_list` | List ICANN contacts for DNS domain registration. Check before creating new contacts. |
| `ud_contact_create` | Create ICANN contact for DNS domain registration. Required before checkout for .com, .org, .net, etc. Suggest user's account email for instant verification. |

## Cart Management

| Tool | Description |
|---|---|
| `ud_cart_get` | Get current shopping cart contents with pricing breakdown. |
| `ud_cart_add_domain_registration` | Add domains for fresh registration. For `marketplace.source = "unstoppable_domains"` with `marketplace.status = "available"`. Max 50 domains. |
| `ud_cart_add_domain_listed` | Add UD marketplace domains to cart. For `marketplace.source = "unstoppable_domains"` with `marketplace.status = "registered-listed-for-sale"`. Supports Lease-to-Own. Max 50. |
| `ud_cart_add_domain_afternic` | Add Afternic marketplace domains to cart. For `marketplace.source = "afternic"`. Max 50. |
| `ud_cart_add_domain_sedo` | Add Sedo marketplace domains to cart. For `marketplace.source = "sedo"`. Max 50. |
| `ud_cart_add_domain_renewal` | Add domain renewals to cart. 1-10 years per domain. Max 50. |
| `ud_cart_remove` | Remove items from shopping cart. |

## Payment & Checkout

| Tool | Description |
|---|---|
| `ud_cart_get_payment_methods` | Get saved credit cards and account balance for checkout. |
| `ud_cart_add_payment_method_url` | Get an authenticated magic link URL to add a new payment method (60s, single-use). |
| `ud_cart_checkout` | Complete checkout. Requires ICANN contact for DNS domains. Uses account balance by default; pass `paymentMethodId` if balance insufficient. |
| `ud_cart_get_url` | Generate authenticated magic link checkout URL for browser purchase (60s, single-use). |

## Marketplace Listings

| Tool | Description |
|---|---|
| `ud_listing_create` | Create marketplace listings (max 50). Set price, offer settings, validity, LTO options. Response may include signing magic link. |
| `ud_listing_update` | Update existing marketplace listings (max 50). May require re-signing. |
| `ud_listing_cancel` | Cancel marketplace listings (max 50). |
| `ud_offers_list` | List incoming offers on domains. Filter by status and domain. |
| `ud_offer_respond` | Accept or reject offers (max 50). Acceptance may require signing. |

## Domain Conversations

| Tool | Description |
|---|---|
| `ud_leads_list` | List conversation threads. Filter by domain. `skipEmpty: true` (default) hides empty threads. |
| `ud_lead_get` | Get or create a conversation for a domain. Returns existing or creates new. |
| `ud_lead_messages_list` | Get messages in a conversation (newest-first, cursor pagination). |
| `ud_lead_message_send` | Send a message in a conversation (max 1000 chars). |

## DNS Records

| Tool | Description |
|---|---|
| `ud_dns_records_list` | List all DNS records for a domain. Filter by type and subName. |
| `ud_dns_record_add` | Add DNS records (max 50). Supports A, AAAA, CNAME, MX, TXT, NS, SRV, CAA. `upsertMode`: append, replace, disallowed (default). Supports `applyToAllDomainsInPortfolio`. |
| `ud_dns_record_update` | Update existing DNS record by record ID. Max 50. |
| `ud_dns_record_remove` | Remove a specific DNS record by ID. Max 50. |
| `ud_dns_records_remove_all` | Remove ALL DNS records from a domain. **Requires `confirmDeleteAll: true`.** Destructive. Supports `applyToAllDomainsInPortfolio`. |

## DNS Nameservers

| Tool | Description |
|---|---|
| `ud_dns_nameservers_list` | List nameservers for a domain. Shows UD default vs custom status and DNSSEC info. |
| `ud_dns_nameservers_set_custom` | Set custom external nameservers (2-12 hostnames). Optional DNSSEC DS records. **Disables** DNS record management. Supports `applyToAllDomainsInPortfolio`. |
| `ud_dns_nameservers_set_default` | Switch back to UD default nameservers. **Re-enables** DNS record management. Supports `applyToAllDomainsInPortfolio`. |

## DNS Hosting

| Tool | Description |
|---|---|
| `ud_dns_hosting_list` | List hosting configs for a domain (listing pages, redirects). |
| `ud_dns_hosting_add` | Add hosting config: `LISTING_PAGE`, `REDIRECT_301`, `REDIRECT_302`. `forceCompatibility: true` auto-switches nameservers. Supports `applyToAllDomainsInPortfolio`. |
| `ud_dns_hosting_remove` | Remove hosting config. `deleteAll: true` with `confirmDeleteAll: true` for all. Supports `applyToAllDomainsInPortfolio`. |

## Domain Operations

| Tool | Description |
|---|---|
| `ud_domain_pending_operations` | List pending operations across domains (up to 50). Use after DNS changes to track propagation. |
| `ud_domain_auto_renewal_update` | Enable or disable auto-renewal for ICANN domains. Supports `applyToAllDomainsInPortfolio`. |

## Domain Management

| Tool | Description |
|---|---|
| `ud_domain_tags_add` | Add tags (up to 10 tags, 20 chars each). Auto-creates new tags. Supports `applyToAllDomainsInPortfolio`. |
| `ud_domain_tags_remove` | Remove tags. Idempotent — skips unapplied tags. Supports `applyToAllDomainsInPortfolio`. |
| `ud_domain_flags_update` | Update WHOIS privacy and transfer lock flags. Supports `applyToAllDomainsInPortfolio`. |
| `ud_domain_push` | Transfer domains to another user by account ID. **Requires MFA (6-digit OTP).** Max 50. |

## Backorders

| Tool | Description |
|---|---|
| `ud_backorder_create` | Create backorders for expiring domains. Requires ICANN contact + availability timestamp. Max 50. |
| `ud_backorders_list` | List user's backorders with status filtering, search, pagination. |
| `ud_backorder_cancel` | Cancel pending backorders. Returns refund information. |

## AI Landing Pages

| Tool | Description |
|---|---|
| `ud_ai_credits_get` | Check AI credit balance and view available packs. New accounts get 5 free credits. |
| `ud_cart_add_ai_credits` | Add AI credit pack to cart by `productCode` or `tierSize`. |
| `ud_domain_generate_lander` | Generate AI-powered landing pages. 1 credit/domain. Custom instructions supported. Async. Supports `applyToAllDomainsInPortfolio`. |
| `ud_domain_lander_status` | Check generation status: pending, generating, processing, hosted, failed, none. Max 50. |
| `ud_domain_download_lander` | Download lander content. Returns `htmlContent` (single-page) or `zipContent` (base64 zip). |
| `ud_domain_upload_lander` | Upload custom lander (HTML or base64 zip). **Requires Domainer Club.** Max 1MB. Supports `applyToAllDomainsInPortfolio`. |
| `ud_domain_remove_lander` | Remove AI landing page. **Destructive.** Supports `applyToAllDomainsInPortfolio`. |

## DNS Presets

| Tool | Description |
|---|---|
| `ud_presets_list` | List saved DNS presets and hardcoded provider presets. |
| `ud_presets_save` | Create or update a preset (nameserver, DNS record, forwarding). Upserts by name. |
| `ud_presets_delete` | Delete a saved preset by type and name. |
| `ud_presets_apply` | Apply a preset to domains. Supports bulk and portfolio-wide. |

## Session Handoff

| Tool | Description |
|---|---|
| `ud_authenticated_url_get` | Generate one-time authenticated URL for browser redirect. Valid 60 seconds, single-use. |
