# Ledgerly — From laptop to landing zone

Demo repository for the 2-hour, presenter-led workshop **"From laptop to landing zone — migrating and
modernizing Ledgerly to Azure"** for system administrators. Presented at **Sinergija 2026**.

**Ledgerly** is a fictional internal *portfolio ledger & reporting* app. "On-prem" means Docker Compose
on the presenter's Windows laptop. During the workshop we **discover** it, **diagram** it with Copilot and
the draw.io MCP server, **migrate** it to Azure (Bicep + azd), **modernize** it (passwordless DB access
with managed identity) and then **break & fix** it three times with real telemetry.

All secrets in this repo are **fake**. `.env` is an intentional legacy anti-pattern.

## Architecture

| | On-prem (as-is) | Azure (to-be), `rg-ledgerly-workshop`, `swedencentral` |
|---|---|---|
| web | nginx 1.25, host **8081** → 80, HTTP | Container App `ca-ledgerly-web-workshop`, external HTTPS ingress → 80 |
| api | Spring Boot 2.7 / Java 11, :8080, `mem_limit 1g` | Container App `ca-ledgerly-api-workshop`, internal ingress → 8080, 1 vCPU / 2Gi, scale 1–5 |
| db | MySQL **5.7** (EOL), host 3307 | Azure Database for MySQL Flexible Server **8.0.21** `mysql-ledgerly-workshop-<sfx>`, B2s, 32 GB |
| cache | Redis 7, no auth | Azure Cache for Redis **Basic C0** `redis-ledgerly-workshop-<sfx>`, TLS 6380 (alt.: Azure Managed Redis) |
| batch | alpine + crond, every 5 min | Container Apps job `caj-ledgerly-batch-workshop`, `*/15 * * * *` |
| secrets | `.env` plaintext | Key Vault `kv-ledgerly-<sfx>` (RBAC) + UAMI `id-ledgerly-workshop` |
| images | local build | ACR `crledgerlyworkshop<sfx>` (Basic, admin disabled, AcrPull via UAMI) |
| observability | none | Log Analytics `log-ledgerly-workshop` + App Insights `appi-ledgerly-workshop`, MySQL slow log |

`<sfx>` = 5-char `uniqueString(subscription, env, location)` – see `azd env get-values`.
Diagrams: `docs/diagrams/ledgerly-as-is.drawio`, `ledgerly-to-be.drawio`.

## Prerequisites

Windows laptop with **Docker Desktop** (Linux containers, ≥ 4 GB RAM), **PowerShell 7**, **VS Code**
(recommended extensions in `.vscode/extensions.json`), **Azure CLI** (+ Bicep), **Azure Developer CLI**,
**git**, **Node.js** (for the Azure MCP Server via `npx`), GitHub Copilot (Agent mode).
Azure subscription with Owner (or Contributor + User Access Administrator) on the subscription.

```powershell
./scripts/00-prereqs.ps1            # add -Register to register resource providers
```

## Local quickstart ("on-prem")

```powershell
./scripts/01-onprem-up.ps1          # docker compose up -d --build, waits for health, opens http://localhost:8081
./scripts/02-discover.ps1           # writes docs/discovery-output.txt
```

First start seeds 200,000 transactions (1–2 min). Host port **8080 is reserved for the draw.io MCP server**,
so Ledgerly web listens on **8081**; MySQL is published on 3307.

## draw.io MCP server

```powershell
docker run -d --name drawio-mcp -p 127.0.0.1:8080:8080 simonkurtzmsft/drawio-mcp-server:latest
curl http://localhost:8080/health    # MCP endpoint: http://localhost:8080/mcp (configured in .vscode/mcp.json)
```

Details, tools and stage flow: [`docs/drawio-mcp.md`](docs/drawio-mcp.md).

### Brand icons (thesvg, C:\Github\tools\thesvg)

Azure icons come from the draw.io MCP server; **non-Azure brand icons** (Docker, nginx, MySQL, Redis, Java/Spring)
come from the presenter's local clone of [glincker/thesvg](https://github.com/glincker/thesvg)
(`public\icons\<slug>\default.svg`), the optional `thesvg` MCP server (`npx -y @thesvg/mcp-server`) or its CDN.
Insert them as image cells (`shape=image;image=data:image/svg+xml,<base64>;aspect=fixed`) or via a custom library:

```powershell
./scripts/build-drawio-library.ps1          # -> docs/diagrams/ledgerly-icons.xml (File > Open Library from > Device)
./scripts/build-drawio-library.ps1 -Search '*spring*','*java*'
```

Diagrams stay self-contained (embedded data, no CDN links); the pre-built `.drawio` files use only built-in shapes.

## Azure quickstart

```powershell
az login ; azd auth login
azd env new workshop                                   # -> rg-ledgerly-workshop
azd env set AZURE_LOCATION swedencentral
azd env set MYSQL_ADMIN_PASSWORD 'Wrkshp-Ledgerly-2026!'   # fake – pick your own
azd env set PRESENTER_IP (Invoke-RestMethod https://api.ipify.org)
azd env set MYSQL_ENTRA_ADMIN_LOGIN (az ad signed-in-user show --query userPrincipalName -o tsv)

azd provision --preview        # what-if – ALWAYS first
azd up                         # provision (placeholder images) + deploy web/api + postdeploy hook builds batch
azd provision                  # 2nd run: real image names now known -> api probes enabled, no placeholder drift

./scripts/03-migrate-data.ps1  # MySQL 5.7 -> Flexible Server 8.0, verifies row counts
./scripts/04-modernize.ps1     # passwordless: UAMI Entra user in MySQL, api -> SPRING_PROFILES_ACTIVE=azure
```

**Bootstrap note:** the first provision runs public placeholder images (`mcr.microsoft.com/k8se/quickstart:latest`,
jobs: `mcr.microsoft.com/k8se/quickstart-jobs:latest`) because ACR is still empty. `azd deploy` pushes the real
web/api images (remote build in ACR); the `postdeploy` hook (`scripts/hooks/postdeploy-batch.ps1`) runs
`az acr build` for `batch/` and `az containerapp job update`, then stores `BATCH_IMAGE_NAME`. Image names are fed
back into Bicep (`SERVICE_WEB_IMAGE_NAME`, `SERVICE_API_IMAGE_NAME`, `BATCH_IMAGE_NAME`) so re-provisioning
does not revert to placeholders. **batch is not an azd service** – it is a Container Apps job.

Break & fix: `scripts/faults/fault-{1,2,3}-*.ps1` and `fix-{1,2,3}-*.ps1`, reset with `scripts/reset.ps1`.
KQL: `kql/queries.kql`. Presenter reference: [`PRESENTER-FACTS.md`](PRESENTER-FACTS.md).

## Checkpoints

`./scripts/make-checkpoints.ps1` (run once on a fresh copy) creates one commit + tag per block. Jump with
`git checkout <tag>`. Details in [`checkpoints.md`](checkpoints.md).

| Tag | Block | Adds |
|---|---|---|
| `00-onprem` | start | app, compose, `.env`, prereqs + up scripts, Copilot/MCP config |
| `01-discovered` | 1 Discover | `02-discover.ps1`, `docs/inventory.md` |
| `02-diagrammed` | 2 Diagram | `docs/diagrams/*.drawio`, `docs/drawio-mcp.md`, icon library script |
| `03-migrated` | 3 Migrate | `azure.yaml`, `infra/`, hook, `03-migrate-data.ps1`, migration plan |
| `04-modernized` | 4 Modernize | `04-modernize.ps1` |
| `05-broken` | 5 Break | fault scripts, `kql/queries.kql` |
| `06-fixed` | 5 Fix | fix scripts, `db/migrations/001-…sql`, reset/cleanup |

## Re-running / reset

- Re-arm faults: `./scripts/reset.ps1` (firewall rule back, api 1 vCPU/2Gi, `JAVA_OPTS` override removed, index dropped).
- Undo block 4: `azd provision` (Bicep re-applies the password-based api config). The MySQL Entra user stays (harmless).
- Re-run the data migration: the dump contains `DROP TABLE IF EXISTS`, so `03-migrate-data.ps1` is repeatable.
- Local index fix for rehearsal: `./scripts/faults/fix-3-slowquery.ps1 -Local`, undo with `./scripts/reset.ps1 -Local`.

## Cleanup

```powershell
./scripts/cleanup.ps1               # azd down --purge --force  +  docker compose down -v
./scripts/cleanup.ps1 -IncludeMcp   # also removes the drawio-mcp container
```

## Repository layout

```
ledgerly/
├─ docker-compose.yml, .env           on-prem stack (legacy)
├─ web/ api/ db/ batch/ cache/        application tiers
├─ azure.yaml, infra/                 azd + Bicep (subscription scope)
├─ scripts/                           PowerShell 7 workshop scripts (+ faults/, hooks/)
├─ kql/queries.kql                    Log Analytics + Resource Graph queries
├─ docs/                              inventory, migration plan, draw.io MCP guide, diagrams
├─ .vscode/ .github/                  MCP servers, extensions, Copilot instructions
└─ checkpoints.md, PRESENTER-FACTS.md
```

All scripts use paths relative to the repo root, so the folder can live anywhere
(any local or synced folder).

## Known gaps / verify before first run

Nothing here was deployed or compiled in the authoring environment (no Azure, Docker, Java or Bicep available).
Run `azd provision --preview`, `az bicep build -f infra/main.bicep` and `docker compose build` once before rehearsal.

1. **Bicep not compiled** – syntax reviewed by hand. API versions used: Microsoft.App 2024-03-01,
   DBforMySQL 2023-12-30, Cache/redis 2024-03-01, KeyVault 2023-07-01, ContainerRegistry 2023-07-01,
   OperationalInsights 2023-09-01, Insights/components 2020-02-02, ManagedIdentity 2023-01-31,
   diagnosticSettings 2021-05-01-preview, roleAssignments 2022-04-01, resourceGroups 2024-03-01.
2. **MySQL Entra admin needs Graph permissions** – Flexible Server requires the server's UAMI
   (`id-ledgerly-mysql-workshop`) to have *User.Read.All, GroupMember.Read.All, Application.Read.All*
   (or the *Directory Readers* role). This needs a tenant admin – grant it **before** the session, otherwise
   block 4 fails at `CREATE AADUSER`. If `MYSQL_ENTRA_ADMIN_LOGIN` is empty, no Entra admin is created.
3. **`CREATE AADUSER '<identity>' IDENTIFIED BY '<client id>'`** + `SET aad_auth_validate_oids_in_tenant = OFF`
   follows Microsoft Learn for Flexible Server – re-check current docs (syntax has changed over time).
4. **Spring Cloud Azure 4.19.0** with Boot 2.7.18 (`spring-cloud-azure-starter-jdbc-mysql`,
   `spring.datasource.azure.passwordless-enabled`, `spring.cloud.azure.credential.managed-identity-enabled`,
   `client-id`) – verify the version exists / is the latest 4.x and that the default (non-azure) profile starts
   cleanly with the starter on the classpath. Code was not compiled (`mvn package` in the Docker build is the first compile).
5. **azd specifics**: `language: docker` for both services, `remoteBuild: true`, and azd setting
   `SERVICE_<NAME>_IMAGE_NAME` after deploy – verify with your azd version. Probes on the api are added only once
   a real image name exists (hence the second `azd provision`).
6. **Internal call `http://ca-ledgerly-api-workshop`** from nginx relies on Container Apps in-environment name
   resolution + `allowInsecure: true` on the api ingress. If it fails, use the internal FQDN
   (`az containerapp show -n ca-ledgerly-api-workshop -g rg-ledgerly-workshop --query properties.configuration.ingress.fqdn`)
   with `https://` and update `API_UPSTREAM`.
7. **Key Vault references / RBAC propagation**: on a brand-new environment the first provision can fail while role
   assignments propagate – simply run `azd provision` again.
8. **Batch job TLS/auth**: Alpine's MariaDB client (`--ssl`) against MySQL 8.0 with `caching_sha2_password`
   is untested; if it fails, the job logs it (and keeps exiting 0 – the legacy smell). Batch still uses the admin
   password via Key Vault (next modernization step: its own Entra user). CSVs land on ephemeral job storage.
9. **Fault 1** adds `-XX:+AlwaysPreTouch` to make the OOMKill deterministic on 1Gi; check the restart loop in rehearsal.
   **Fault 3** timings depend on B2s burst credits – `log_queries_not_using_indexes=ON` guarantees slow-log evidence.
10. **Container Apps log tables**: environment uses destination `log-analytics` → `*_CL` tables; column names
    (`Reason_s`, `Log_s`, …) can differ slightly – both variants are in `kql/queries.kql`.
11. **draw.io icons**: pre-built diagrams reference `img/lib/azure2/...` names believed to exist
    (Subscriptions, Resource_Groups, Azure_Database_MySQL_Server, Cache_Redis, Key_Vaults, Container_Registries,
    Managed_Identities). If one renders blank, replace it in the editor; Container Apps, Log Analytics and
    App Insights are deliberately Azure-blue rounded rectangles.
12. **thesvg slugs** (`openjdk`, `spring`, `visualstudiocode`, `microsoftazure`, …) and the `@thesvg/mcp-server` package name were not verified here – the library script skips missing slugs; use `-Search`.
13. `mysql:5.7` is amd64-only (fine on Windows/x64; emulated on ARM). App Insights Java agent 3.5.4 is attached only
    when `APPLICATIONINSIGHTS_CONNECTION_STRING` is set.
