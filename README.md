# Unstoppable Domains Skills

Agent skills for searching, registering, and managing domain names with [Unstoppable Domains](https://unstoppabledomains.com). Covers both the **User API** (MCP server, CLI, REST) for individual domain management and the **Reseller API** for building domain registration platforms.

## What You Get

Installing this plugin gives your agent:

- **MCP server connection** — automatically configured on install
- **3 skills** covering the full domain lifecycle:
  - **Setup** — MCP server config, CLI installation, API key and OAuth authentication
  - **Domains** — search, purchase, DNS, portfolio management, marketplace listings, offers, AI landing pages, backorders, troubleshooting, and 60+ tool reference
  - **Reseller API** — partner REST API for building white-label domain registration platforms

## APIs Covered

| API | Audience | Access Methods |
|---|---|---|
| **User API** | Individuals managing their own domains | MCP server, CLI (`ud`), REST API |
| **Reseller API** | Developers building domain registration platforms | REST API (`/partner/v3`) |

The **User API** powers domain search, purchase, DNS management, marketplace operations, and AI landing pages for individual users. The **Reseller API** provides domain search, registration, DNS management, and lifecycle operations for reseller partners offering domain services to their end users.

## Installation

### Claude Web / Desktop

1. Open Claude Desktop settings
2. Navigate to **Connectors** > **Customize**
3. Click **Add Plugin** > **Create Plugin** > **Add Marketplace**
4. Search for **unstoppable-domains/skills**
5. Select **Install now**

This installs both the skills and the MCP server connection.

To install the MCP server manually, add to your config file:

- **macOS:** `~/Library/Application Support/Claude/claude_desktop_config.json`
- **Windows:** `%APPDATA%\Claude\claude_desktop_config.json`
- **Linux:** `~/.config/Claude/claude_desktop_config.json`

```json
{
  "mcpServers": {
    "unstoppable-domains": {
      "url": "https://api.unstoppabledomains.com/mcp/v1/"
    }
  }
}
```

### Claude Code

```bash
/plugin install unstoppable-domains
```

This installs both the skills and the MCP server connection. No separate MCP setup needed.

Or add the marketplace first for direct access:

```bash
/plugin marketplace add unstoppabledomains/skills
/plugin install unstoppable-domains@skills
```

To install the MCP server only (without skills):

```bash
claude mcp add unstoppable-domains --transport http https://api.unstoppabledomains.com/mcp/v1/
```

### Cursor

```text
/plugin-add unstoppable-domains
```

### CLI

```bash
# macOS / Linux
curl -fsSL https://raw.githubusercontent.com/unstoppabledomains/ud-cli/main/install.sh | sh

# npm
npm install -g @unstoppabledomains/ud-cli

# Build from source
git clone https://github.com/unstoppabledomains/ud-cli.git
cd ud-cli
npm install
npm run build
npm install -g .
```

## What Can You Do?

With these skills, your agent can:

- **Search & buy domains** — find available .com, .net, .org, .io, .ai domains, check pricing, complete purchases
- **Configure DNS** — set up A, CNAME, MX, TXT records, point to web servers, configure email
- **Manage your portfolio** — view domains, track expirations, set up auto-renewal, organize with tags
- **Sell on the marketplace** — list domains, set prices, manage offers, negotiate with buyers
- **Generate AI landing pages** — create branded landing pages for parked domains
- **Backorder expiring domains** — monitor pending-delete inventory and auto-register when they drop
- **Build reseller platforms** — full REST API for white-label domain registration

## Authentication

### User API (MCP / CLI)

- **OAuth 2.0** (recommended) — browser-based, scoped permissions
- **API Key** — generate at [Account Settings > Advanced](https://unstoppabledomains.com/account/settings?tab=advanced), format: `ud_mcp_*`

### Reseller API

- **API Key** — obtain from the [Reseller Dashboard](https://unstoppabledomains.com/reseller-dashboard), use as Bearer token

## Resources

| Resource | URL |
|---|---|
| User API Documentation | https://unstoppabledomains.com/docs/mcp.md |
| User API OpenAPI Spec | https://api.unstoppabledomains.com/mcp/v1/openapi.json |
| Reseller API Documentation | https://docs.unstoppabledomains.com/apis/reseller/openapi |
| Reseller Quick Start | https://docs.unstoppabledomains.com/apis/reseller/quick-start |
| CLI Repository | https://github.com/unstoppabledomains/ud-cli |
| Reseller Dashboard | https://unstoppabledomains.com/reseller-dashboard |
| Support | support@unstoppabledomains.com |

## Contributing

1. Fork this repository
2. Create a branch for your changes
3. Submit a PR

## License

MIT License — see [LICENSE](LICENSE) for details.
