---
name: setup
description: >-
  Use when setting up Unstoppable Domains MCP server, installing the UD CLI,
  generating an API key, authenticating with OAuth, or connecting AI tools to
  Unstoppable Domains for domain management.
---

# Unstoppable Domains Setup

Connect to the Unstoppable Domains platform via MCP server, CLI, or API key.

## MCP Server

**Claude Code:**
```bash
claude mcp add unstoppable-domains --transport http https://api.unstoppabledomains.com/mcp/v1/
```

**Claude Desktop** — add to your config file (`~/Library/Application Support/Claude/claude_desktop_config.json` on macOS):
```json
{
  "mcpServers": {
    "unstoppable-domains": {
      "url": "https://api.unstoppabledomains.com/mcp/v1/"
    }
  }
}
```

Verify: `claude mcp list`

## CLI

**macOS / Linux:**
```bash
curl -fsSL https://raw.githubusercontent.com/unstoppabledomains/ud-cli/main/install.sh | sh
```

**npm:**
```bash
npm install -g @unstoppabledomains/ud-cli
```

**Build from source:**
```bash
git clone https://github.com/unstoppabledomains/ud-cli.git
cd ud-cli
npm install
npm run build
npm install -g .
```

Verify: `ud --help`

## Authentication

**OAuth 2.0 (recommended)** — browser-based with scoped permissions:
```bash
ud auth login
```

**API Key** — generate at [Account Settings > Advanced](https://unstoppabledomains.com/account/settings?tab=advanced). Format: `ud_mcp_*`
```bash
ud auth login --key ud_mcp_your_key_here
```

**Headless Signup** (no browser needed):
```bash
ud auth signup
```

Check status: `ud auth status` | Logout: `ud auth logout`

Credentials stored in system keychain (macOS Keychain, Windows Credential Vault, Linux Secret Service).

## OAuth Scopes

| Scope | Access |
|---|---|
| `domains:search` | Search domains, check availability |
| `portfolio:read` | View domains, DNS records, offers |
| `portfolio:write` | Manage DNS, create listings, send messages |
| `cart:read` | View cart and payment methods |
| `cart:write` | Add/remove cart items |
| `checkout` | Complete purchases |

## Session Handoff

For browser actions, use `ud_authenticated_url_get` to generate a one-time magic link that signs the user in automatically. Valid 60 seconds, single-use.

## Resources

- **Full docs:** https://unstoppabledomains.com/docs/mcp.md
- **OpenAPI spec:** https://api.unstoppabledomains.com/mcp/v1/openapi.json
- **OAuth metadata:** https://api.unstoppabledomains.com/.well-known/oauth-authorization-server
- **Support:** support@unstoppabledomains.com
