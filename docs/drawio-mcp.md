# Block 2 – diagrams with Copilot + the draw.io MCP server

The presenter uses **drawio-mcp-server** by Simon Kurtz (`simonkurtz-MSFT/drawio-mcp-server`), running
locally in Docker. It is a **standalone, stateless draw.io XML generator** – no browser or draw.io
instance needed – with **700+ embedded official Azure architecture icons** (base64 SVG, works offline).

## Start it

```powershell
# recommended: bind to loopback only – the endpoint has no authentication
docker run -d --name drawio-mcp -p 127.0.0.1:8080:8080 simonkurtzmsft/drawio-mcp-server:latest

curl http://localhost:8080/health          # health check
# MCP endpoint (Streamable HTTP): http://localhost:8080/mcp
```

> The presenter's current container maps `8080:8080` (all interfaces) – re-create it with
> `127.0.0.1:8080:8080` before the session. Because the MCP server owns host port **8080**,
> Ledgerly's on-prem web is published on **8081** (`http://localhost:8081`).

VS Code picks it up from `.vscode/mcp.json`:

```json
"drawio": { "type": "http", "url": "http://localhost:8080/mcp" }
```

## Tools (used on stage in **bold**)

| Area | Tools |
|---|---|
| Shapes | **`search-shapes`** (fuzzy; pass all terms at once in the `queries` array), `get-shape-categories`, `get-shapes-in-category`, `get-style-presets` |
| Cells | **`add-cells`** (vertices + edges in one batch; `shape_name` resolves icons; `temp_id` lets edges reference new vertices; `dry_run` to validate), `edit-cells`, `edit-edges`, `set-cell-shape`, `delete-cell-by-id` |
| Groups | **`create-groups`**, `add-cells-to-group`, `remove-cell-from-group`, `list-group-children` – use for the **resource group**, the **Container Apps environment** and the **laptop/Docker host boundary** |
| Pages / layers | **`create-page`**, `list-pages`, `get-active-page`, `set-active-page`, `rename-page`, `delete-page`; `list-layers`, `set-active-layer`, `create-layer`, `move-cell-to-layer` |
| Model | `list-paged-model`, `get-diagram-stats`, **`export-diagram`**, `import-diagram`, `clear-diagram` |

**Stateless contract:** every call takes the full previous `diagram_xml` and returns a new one – Copilot
must carry the returned `diagram_xml` forward into the next call. If a call is made without it, the
diagram silently starts from empty (classic "Copilot got it wrong" moment – `get-diagram-stats` shows it).

## Stage flow (≈ 15 min)

1. Copilot Chat → **Agent mode**, tools `drawio` enabled. `#file:docker-compose.yml` in context.
2. `search-shapes` with `queries: ["container apps environment", "container apps", "mysql flexible", "cache redis", "key vaults", "container registries", "managed identities", "log analytics", "application insights", "resource groups"]`.
3. `import-diagram` with `docs/diagrams/ledgerly-starter.drawio` (title + legend) – optional.
4. **As-is page**: `create-groups` (laptop / Docker host) → `add-cells` (5 containers, 2 volumes, `.env` note; edges by `temp_id`); brand icons for Docker/nginx/MySQL/Redis/Java from **thesvg** as embedded image cells (see below).
5. `create-page` "to-be" → `create-groups` (rg-ledgerly-workshop, cae-ledgerly-workshop) → `add-cells` in one batch (icons via `shape_name`, edges with labels: HTTPS, internal HTTP, TLS 3306/6380, secret refs, AcrPull, logs).
6. `get-diagram-stats` (sanity: pages, cell and edge counts) → `export-diagram`.
7. Save the XML as `docs/diagrams/ledgerly-live.drawio` → opens in the **draw.io VS Code extension** (`hediet.vscode-drawio`) → tidy by hand → commit.

### Prompts (off-screen copy/paste)

- *"Read docker-compose.yml and draw the as-is architecture with the drawio tools: a group 'Windows laptop · Docker Desktop' containing web (host 8081→80), api (:8080, mem_limit 1g), db mysql:5.7 (host 3307→3306), cache redis:7, batch cron; volumes db-data and reports; .env as a red note. Use add-cells in ONE batch with temp_id edges and carry diagram_xml forward."*
- *"Add a second page 'to-be' following infra/main.bicep: groups for rg-ledgerly-workshop and cae-ledgerly-workshop; search-shapes for the Azure icons first (all queries in one call); label every resource with its exact name from infra/main.bicep."*
- *"Run get-diagram-stats, then export-diagram and save the XML to docs/diagrams/ledgerly-live.drawio."*

## Fallback (no MCP / no network)

Pre-built, valid uncompressed files in `docs/diagrams/` render anywhere (built-in draw.io shapes only):

| File | Content |
|---|---|
| `ledgerly-as-is.drawio` | laptop / Docker host boundary, 5 containers, ports, volumes, flows, risks |
| `ledgerly-to-be.drawio` | subscription › rg-ledgerly-workshop › Container Apps env (web, api, batch job), MySQL, Redis, Key Vault, ACR, UAMI, Log Analytics, App Insights, flows |
| `ledgerly-starter.drawio` | blank page with title + legend |

Open them with the draw.io VS Code extension (`hediet.vscode-drawio`) – Bicep visualizer is the second fallback for the to-be view.

## Brand icons from thesvg (C:\Github\tools\thesvg)

Combined flow: the **draw.io MCP server** (`:8080`) provides Azure icons and layout; **thesvg**
([glincker/thesvg](https://github.com/glincker/thesvg), 7,600+ official brand + cloud SVGs, MIT code) provides the
**non-Azure brand icons** – Docker, nginx, MySQL, Redis, Java/Spring – mainly for the as-is page.

| Source | How |
|---|---|
| Local clone `C:\Github\tools\thesvg` | `public\icons\<slug>\<variant>.svg` (variants `default`, `mono`, `light`, `dark`, `wordmark`; `default` always exists). Manifest: `src\data\icons.json` |
| thesvg MCP server | optional server `thesvg` in `.vscode/mcp.json` (`npx -y @thesvg/mcp-server`) – Copilot can look up icons by name during the demo |
| CDN (rehearsal only) | `https://thesvg.org/icons/<slug>/default.svg` or `https://cdn.jsdelivr.net/gh/glincker/thesvg@main/public/icons/<slug>/default.svg`; registry `https://thesvg.org/api/registry.json` |

Ways to get them into the diagram:

- **Image cells via Copilot**: after `add-cells` for the containers, ask Copilot to read `public\icons\docker\default.svg`
  (or fetch it via the thesvg MCP server), base64-encode it and set the style
  `shape=image;image=data:image/svg+xml,<base64>;aspect=fixed;` (with `edit-cells` / `set-cell-shape` or directly in `add-cells`).
  Note: no `;base64` in the data URI inside a draw.io style – the `;` would break the style string.
- **Custom library**: `./scripts/build-drawio-library.ps1` reads `public\icons\<slug>\default.svg` for
  `docker, nginx, mysql, redis, openjdk, spring, github, visualstudiocode, powershell, microsoftazure`
  (missing slugs are skipped with a warning; `-Search '*spring*'` finds folder names) and writes
  `docs/diagrams/ledgerly-icons.xml`. Open it via *File › Open Library from › Device* and drag icons onto the canvas.
- **Drag & drop**: drag SVGs from the folder onto the VS Code draw.io canvas.

Keep diagrams **self-contained**: embed icons as data URIs, never link the CDN or a `file:///` path.
The pre-built `.drawio` files use only built-in draw.io shapes so they render anywhere.
