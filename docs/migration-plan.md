# Ledgerly – migration plan

## 6R decision per component

| Component | Decision | Target | Why |
|---|---|---|---|
| web (nginx) | **Rehost** (container lift & shift) | Container App `ca-ledgerly-web-workshop`, external ingress (HTTPS) | Stateless; only the upstream URL changes (`API_UPSTREAM`) |
| api (Spring Boot) | **Rehost → Refactor (light)** | Container App `ca-ledgerly-api-workshop`, internal ingress :8080 | Same image first; block 4 adds passwordless DB auth (profile `azure`). Later: Java 17/21 + Boot 3 (Replatform/Refactor) |
| db (MySQL 5.7) | **Replatform** | Azure Database for MySQL Flexible Server **8.0.21** `mysql-ledgerly-workshop-<sfx>` | 5.7 is EOL; managed backups, patching, slow-log, Entra auth |
| cache (Redis) | **Replatform** | Azure Cache for Redis **Basic C0** `redis-ledgerly-workshop-<sfx>` (TLS :6380) | Managed; key in Key Vault. Alternative: **Azure Managed Redis** for new builds |
| batch (cron) | **Replatform** | Container Apps **job** `caj-ledgerly-batch-workshop`, `*/15 * * * *` | Scheduler is the platform; runs once & exits (`RUN_ONCE=true`) |
| `.env` secrets | **Retire** | Key Vault `kv-ledgerly-<sfx>` + managed identity `id-ledgerly-workshop` | No secrets in files; API ends up with **no DB password at all** |
| reports volume | **Retain (for now)** | ephemeral job storage | Follow-up: write CSVs to Blob Storage / Azure Files |

## MySQL 5.7 → 8.0 compatibility checks

Run by `scripts/03-migrate-data.ps1` before the dump (Microsoft also offers the MySQL Shell
`util.checkForServerUpgrade()` upgrade checker – optional extra).

| Check | Ledgerly result | Action |
|---|---|---|
| Character set `utf8` (= utf8mb3) | all 4 tables | Works on 8.0 with deprecation warning; convert to `utf8mb4` later (`ALTER TABLE … CONVERT TO CHARACTER SET utf8mb4`) |
| Reserved words new in 8.0 (`RANK`, `GROUPS`, `LEAD`, `LAG`, `SYSTEM`, …) | none | – |
| Removed sql_mode `NO_AUTO_CREATE_USER` in routine definitions | no routines/triggers/views | – |
| Default auth plugin `caching_sha2_password` | app uses Connector/J 8.0.33 (supports it); batch uses MariaDB client | Batch verified with admin user (see README Known gaps) |
| Tables without primary key | none | – (`sql_require_primary_key` safe) |
| Implicit `GROUP BY` sorting removed in 8.0 | app queries use explicit `ORDER BY` | – |
| `ZEROFILL`, display widths, `utf8mb3` collation names | none relevant | – |
| TLS required by server | 8.0 Flexible Server `require_secure_transport=ON` | api `sslMode=REQUIRED`, batch `--ssl`, client `--ssl-mode=REQUIRED` |

## Migration method

Offline dump & restore (small DB, ~10 MB, minutes): `mysqldump --single-transaction --routines --triggers
--set-gtid-purged=OFF` inside the 5.7 container → import with a temporary `mysql:8.0` client container
(`--ssl-mode=REQUIRED`) over the firewall rule `AllowPresenterIp`. For large/online migrations use
Azure Database Migration Service or data-in replication.

## Cutover

1. **T-1 day**: `azd up` (infra + images), rehearse `03-migrate-data.ps1`, validate row counts, keep the DB.
2. **Freeze**: `./scripts/03-migrate-data.ps1 -FreezeSource` stops on-prem `api` and `batch` (read-only window).
3. Dump → import → **row counts must match** (script aborts otherwise).
4. Smoke test: `WEB_URI` → health badge **UP**, portfolios list, positions, *Run monthly report*.
5. Switch users to `WEB_URI` (DNS/bookmark). On-prem stays stopped but **intact** for rollback.

## Rollback

- Before users write to Azure: `docker compose start api batch` → back on-prem, zero data loss.
- After writes in Azure: dump Azure DB (`mysqldump` from `mysql:8.0` client with
  `--set-gtid-purged=OFF --column-statistics=0`) and restore on-prem (8.0 → 5.7 downgrade risk: check
  utf8mb4_0900 collations) – therefore keep the rollback window short and agreed upfront.
- Infra rollback: `azd down --purge --force` (on-prem untouched).
