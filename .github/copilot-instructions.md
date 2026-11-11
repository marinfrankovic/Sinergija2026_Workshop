# Copilot instructions – Ledgerly

You are helping migrate and modernize **Ledgerly** (portfolio ledger & reporting) from Docker Compose
"on-prem" to Azure. Follow these standards in every suggestion, file and command.

## Naming
- Pattern: `<type>-ledgerly-<env>`; add a component segment when there are several of a type:
  `ca-ledgerly-api-workshop`, `ca-ledgerly-web-workshop`, `caj-ledgerly-batch-workshop`.
- Globally unique names get a 5-char `uniqueString` suffix: `mysql-ledgerly-workshop-<sfx>`,
  `redis-ledgerly-workshop-<sfx>`, `kv-ledgerly-<sfx>` (24-char limit), `crledgerlyworkshop<sfx>` (alphanumeric).
- Resource group: `rg-ledgerly-workshop`, region `swedencentral`.

## Tags (required on every resource)
`owner`, `environment`, `costCenter`, `workload` (= `ledgerly`).

## Security
- **No secrets in code**, compose files, Bicep parameters files or scripts. Use Key Vault + secure params.
  (`.env` in this repo is the intentional legacy anti-pattern – never copy it.)
- **Managed identity first**: user-assigned identity `id-ledgerly-<env>` for ACR pull, Key Vault, MySQL (Entra).
- **Private by default where feasible**; if public access is used for the workshop, say so in a comment
  and restrict it (firewall rules, internal ingress for the API).
- Key Vault in RBAC mode; least-privilege role assignments (Secrets User for apps).

## Infrastructure as code
- Bicep + Azure Developer CLI (`azure.yaml`, `infra/`). Modules per concern in `infra/modules`.
- Use the **latest stable (non-preview) API versions** you can verify; never invent properties –
  if unsure, say so and point to the Microsoft Learn reference.
- **Always run what-if before deploy**: `azd provision --preview` or `az deployment sub what-if`.
- Container Apps: liveness/readiness probes on `/api/health`, scale rules, CPU/memory consistent with JVM settings.

## Code
- API: Spring Boot (currently 2.7 / Java 11 – legacy), JdbcTemplate, Redis cache-aside, config via env vars.
- Scripts: PowerShell 7, header comment block, `$ErrorActionPreference = 'Stop'`, relative paths only.
- SQL must run on MySQL 5.7 (source) **and** 8.0 (target) unless explicitly target-only.
