# PRESENTER FACTS — Ledgerly workshop (2 h)

"From laptop to landing zone — migrating and modernizing Ledgerly to Azure" · Sinergija 2026
Audience: system administrators · Windows laptop, Docker Desktop, PowerShell 7, VS Code + GitHub Copilot (Agent mode)

## Exact names

| Thing | Value |
|---|---|
| azd env / region | `workshop` / `swedencentral` |
| Resource group | `rg-ledgerly-workshop` (tags: owner, environment, costCenter, workload=ledgerly) |
| Container Apps env | `cae-ledgerly-workshop` (Consumption, logs → Log Analytics) |
| Web app | `ca-ledgerly-web-workshop` – external HTTPS ingress → 80 – URL = `WEB_URI` |
| API app | `ca-ledgerly-api-workshop` – internal ingress → 8080 – 1 vCPU / 2Gi – scale 1–5 @ 50 concurrent |
| Batch job | `caj-ledgerly-batch-workshop` – schedule `*/15 * * * *`, `RUN_ONCE=true` |
| MySQL | `mysql-ledgerly-workshop-<sfx>` – 8.0.21, Burstable B2s, 32 GB, db `ledgerly`, admin `ledgerlyadmin` |
| MySQL firewall | `AllowAllAzureServices` (0.0.0.0) + `AllowPresenterIp` |
| MySQL params | `slow_query_log=ON`, `long_query_time=2`, `log_queries_not_using_indexes=ON`; diag → `MySqlSlowLogs` |
| Redis | `redis-ledgerly-workshop-<sfx>` – Basic C0, TLS 6380 (alt. Azure Managed Redis) |
| Key Vault | `kv-ledgerly-<sfx>` – RBAC – secrets `mysql-admin-password`, `redis-password` |
| ACR | `crledgerlyworkshop<sfx>` – Basic, admin disabled |
| Identities | `id-ledgerly-workshop` (apps: AcrPull, KV Secrets User, MySQL Entra user) · `id-ledgerly-mysql-workshop` (MySQL server, Entra lookup) |
| Monitoring | `log-ledgerly-workshop`, `appi-ledgerly-workshop` |
| Placeholder images | `mcr.microsoft.com/k8se/quickstart:latest`, jobs `mcr.microsoft.com/k8se/quickstart-jobs:latest` |

## Ports & URLs

| | |
|---|---|
| Ledgerly on-prem web | **http://localhost:8081** (compose `8081:80`, HTTP only) |
| draw.io MCP server | **http://localhost:8080/mcp** · health **http://localhost:8080/health** |
| On-prem MySQL | localhost:**3307** → 3306 (legacy smell) |
| api / cache | internal only (8080 / 6379) |
| Azure web | `azd env get-value WEB_URI` → `https://ca-ledgerly-web-workshop.<env-domain>.swedencentral.azurecontainerapps.io` |

## Env vars (api)

`DB_HOST DB_PORT DB_NAME DB_USER DB_PASSWORD DB_SSL_MODE REDIS_HOST REDIS_PORT REDIS_PASSWORD REDIS_SSL`
+ Azure: `AZURE_CLIENT_ID`, `APPLICATIONINSIGHTS_CONNECTION_STRING`, block 4: `SPRING_PROFILES_ACTIVE=azure`, `DB_USER=id-ledgerly-workshop`, **no** `DB_PASSWORD`.
Image default: `JAVA_OPTS=-Xms1g -Xmx2g` (compose `mem_limit: 1g`).

## Endpoints

`GET /api/health` (always 200; `status` UP/DEGRADED, `db`, `cache`, `host`) · `GET /api/portfolios` (Redis cache-aside) ·
`GET /api/portfolios/{id}/positions` · `GET /api/reports/monthly?year=2025&month=6` (slow: N+1 full scans) · `POST /api/reports/run`.
Data: 12 portfolios, 30 instruments, 360 positions, **200,000 transactions** (2024-01-01 … 2025-12-31).

## Timeline & commands per block

| Time | Block | Commands | Expected output |
|---|---|---|---|
| 0–8 | Intro | browser `http://localhost:8081`; slide with story | UI with 12 portfolios, green badge `UP · db UP · cache UP` |
| 8–28 | **1 Discover** | `./scripts/02-discover.ps1` · Copilot reads compose/.env/Dockerfiles · compare with `docs/inventory.md` | 5 services; mysql 5.7.x; 200,000 rows; secrets masked; **RISK: -Xmx (2048 MiB) >= container limit (1024 MiB)**; transactions only has `PRIMARY` index |
| 28–43 | **2 Diagram** | Agent mode + `drawio` MCP (+ `thesvg`) → save `docs/diagrams/ledgerly-live.drawio` → open in VS Code | as-is + to-be pages; fallback: pre-built `.drawio` files |
| 43–70 | **3 Migrate** | `azd provision --preview` → (`azd deploy web` live, optional) → `./scripts/03-migrate-data.ps1` → open `WEB_URI` | what-if: no changes (pre-provisioned); row counts table all `True`; target `8.0.21`; Azure UI with same data |
| 70–90 | **4 Modernize** | `./scripts/04-modernize.ps1` · show env vars + Key Vault + Copilot app-modernization talk (Java 17/21, Boot 3) | `CREATE AADUSER` ok; new revision; health `UP`; env list without `DB_PASSWORD` |
| 90–110 | **5 Break & fix** | `faults/fault-N` → evidence (portal, KQL, Azure MCP) → `faults/fix-N` | see faults below |
| 110–120 | Wrap-up | Resource Graph query, cost by tags, `cleanup.ps1` (after session) | |

### Stage flow – diagram block

Agent mode → **search-shapes** (all Azure queries in one `queries` array) → **create-groups** (rg-ledgerly-workshop, cae-ledgerly-workshop; laptop boundary on as-is) →
**add-cells** (one batch, `shape_name` icons, edges by `temp_id`) → brand icons (Docker, nginx, MySQL, Redis, Java/Spring) from **thesvg**
(local clone `C:\Github\tools\thesvg\public\icons\<slug>\default.svg`, `thesvg` MCP, or `docs/diagrams/ledgerly-icons.xml` library) as
`shape=image;image=data:image/svg+xml,<base64>;aspect=fixed` → **create-page** "to-be" → **get-diagram-stats** → **export-diagram** →
save `.drawio` → open in VS Code draw.io editor (`hediet.vscode-drawio`) → tidy → **commit**.
Stateless server: every call must carry the previous `diagram_xml` forward.

## The three faults

| # | Inject | Symptom | Evidence | Root cause | Fix |
|---|---|---|---|---|---|
| 1 OOM | `faults/fault-1-oom.ps1` (api 0.5 vCPU/1Gi, `JAVA_OPTS=-Xms1g -Xmx2g -XX:+AlwaysPreTouch`) | 502 / badge "API DOWN", revision never healthy | `az containerapp replica list` restartCount ↑; `az containerapp logs show --type system`; KQL #1 (OOMKilled / exit 137) | JVM heap hard-coded above container memory | `faults/fix-1-oom.ps1` → 1 vCPU/2Gi + `JAVA_OPTS=-XX:MaxRAMPercentage=75.0`; permanent: remove ENV from Dockerfile |
| 2 Network | `faults/fault-2-network.ps1` (delete `AllowAllAzureServices`, restart revision) | badge `DEGRADED · db DOWN`, portfolios 500 after ~5 s | KQL #2 "Connection is not available… timed out"; App Insights failed dependencies (KQL #3); `az mysql flexible-server firewall-rule list` | "hardening" removed the only path from Container Apps to MySQL | `faults/fix-2-network.ps1` recreate rule; long-term VNet + private access |
| 3 Slow query | `faults/fault-3-slowquery.ps1` (40 calls, 8 parallel) | report button spins, seconds per call | KQL #4 requests > 2000 ms; KQL #5 `AzureDiagnostics` `MySqlSlowLogs` (rows_examined ≈ 200k); EXPLAIN `type=ALL` | no index on `transactions.booking_date` + N+1 | `faults/fix-3-slowquery.ps1` → `CREATE INDEX ix_transactions_booking_date ON transactions(booking_date)`; EXPLAIN `type=range` |

Re-arm: `./scripts/reset.ps1` (rehearsal locally: `fault-3 -Local`, `fix-3 -Local`, `reset.ps1 -Local`).

## Off-screen Copilot prompts

**1 Discover**
- "Read docker-compose.yml, .env and both Dockerfiles. Produce an inventory table: service, image, version, ports, volumes, env vars (mask secrets), and the top 5 migration risks."
- "Compare the api JAVA_OPTS with the container memory limit. What happens under load?"
- "Which MySQL 5.7 → 8.0 incompatibilities should I check in db/init/*.sql?"

**2 Diagram**
- "Use the drawio tools: search-shapes for all Azure icons in one call, then create-groups for rg-ledgerly-workshop and cae-ledgerly-workshop, then add-cells in one batch using temp_id edges. Use exact names from infra/main.bicep."
- "For the as-is page use thesvg icons for docker, nginx, mysql, redis and openjdk as embedded image cells."
- "get-diagram-stats, export-diagram, save to docs/diagrams/ledgerly-live.drawio."

**3 Migrate**
- "Explain infra/main.bicep module by module and list every role assignment."
- "Run azd provision --preview and summarise the what-if."
- "Write the mysqldump command for a 5.7 source going to Azure MySQL 8.0 – which flags matter?"

**4 Modernize**
- "How do I make the Spring Boot 2.7 api connect to Azure MySQL without a password using the user-assigned identity?"
- "Which secrets can now be removed from the api Container App?"
- "What would an upgrade to Spring Boot 3 / Java 21 involve for this pom.xml?"

**5 Break & fix** (Azure MCP)
- "Why is my container app ca-ledgerly-api-workshop restarting?"
- "Show failed dependencies for appi-ledgerly-workshop in the last 30 minutes."
- "Which queries in the MySQL slow log examine the most rows?"

## "Copilot got it wrong" moments (and what catches it)

| Block | Likely mistake | Caught by |
|---|---|---|
| 1 | Reports web port 8080 (container port) instead of host **8081**, or misses the 5.7 EOL | `02-discover.ps1` port map / version output |
| 2 | Forgets to pass `diagram_xml` → second call starts empty; invents icon names | `get-diagram-stats` cell count; `search-shapes` results; `dry_run` |
| 3 | Suggests a preview/old API version or a non-existent property (e.g. MySQL `authConfig` copied from PostgreSQL) | Bicep extension squiggles, `az bicep build`, `azd provision --preview` |
| 4 | Uses `CREATE USER … IDENTIFIED WITH aad_auth` or the wrong client id / object id | `04-modernize.ps1` output, `SELECT user, plugin FROM mysql.user`, health badge |
| 5 | Blames MySQL CPU for fault 1, or proposes "just add memory" | KQL restart/OOM evidence, replica restartCount, `JAVA_OPTS` in the revision env |

## Extras

- **Resource Graph**: `resources | where resourceGroup =~ 'rg-ledgerly-workshop' | project name, type, location, sku, tags`
  (`az graph query -q "..."`, last query in `kql/queries.kql`).
- **Bicep visualizer**: open `infra/main.bicep` → *Bicep: Open Visualizer* (to-be diagram for free).
- **Copilot CLI**: `copilot` in the terminal – "explain scripts/03-migrate-data.ps1".
- **Azure MCP**: "why is my container app restarting?" (server `azure` in `.vscode/mcp.json`).
- **Checkpoints**: `git checkout 03-migrated` etc. (`checkpoints.md`).
- **Cost**: tags `costCenter`/`workload` → Cost Management *group by tag*; Pricing Calculator for B2s MySQL, C0 Redis, ACR Basic, Consumption Container Apps. Tear down after the session: `./scripts/cleanup.ps1`.

## Pre-session checklist

**Day before**
- [ ] Tenant admin granted Graph permissions (or Directory Readers) to `id-ledgerly-mysql-workshop` (needed for MySQL Entra admin).
- [ ] `az login`, `azd auth login`, `azd env select workshop`, env values set (location, `MYSQL_ADMIN_PASSWORD`, `PRESENTER_IP`, `MYSQL_ENTRA_ADMIN_LOGIN`).
- [ ] **Pre-provision** – MySQL Flexible Server takes minutes: `azd up` then `azd provision` again (probes + real images).
- [ ] Rehearse 03 → 04 → faults; then `azd provision` (undo block 4) + `reset.ps1`; optionally keep data migrated.
- [ ] `make-checkpoints.ps1` on the presentation copy; `build-drawio-library.ps1` for thesvg icons.

**1 hour before**
- [ ] `docker run -d --name drawio-mcp -p 127.0.0.1:8080:8080 simonkurtzmsft/drawio-mcp-server:latest` ; `curl http://localhost:8080/health`
- [ ] `./scripts/01-onprem-up.ps1` → http://localhost:8081 green badge
- [ ] `./scripts/00-prereqs.ps1` all OK; public IP unchanged (else `azd env set PRESENTER_IP …` + `azd provision`)
- [ ] VS Code: MCP servers `drawio`, `azure`, `thesvg` started; Copilot Agent mode; font size up; notifications off
- [ ] Portal tabs: rg-ledgerly-workshop, Log Analytics (queries pasted), App Insights failures, Container App revisions
