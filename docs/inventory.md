# Ledgerly – inventory (expected discovery answer)

> Produced in block 1 from `docker-compose.yml`, `.env`, the Dockerfiles and `scripts/02-discover.ps1`
> (raw output: `docs/discovery-output.txt`). Numbers marked ≈ depend on the laptop – confirm in rehearsal.

## Components

| Service | Image / build | Runtime version | Ports (host → container) | Volumes / mounts | Notes |
|---|---|---|---|---|---|
| `web` | `ledgerly/web:1.0` ← `nginx:1.25-alpine` | nginx 1.25 | **8081 → 80** (HTTP only) | – | Static UI + reverse proxy `/api/` → `api:8080` (`API_UPSTREAM`) |
| `api` | `ledgerly/api:1.0` ← `eclipse-temurin:11-jre` | Spring Boot **2.7.18**, Java **11** | 8080 (internal only) | – | `mem_limit: 1g`, image `JAVA_OPTS=-Xms1g -Xmx2g`; JdbcTemplate + Redis cache-aside |
| `db` | `mysql:5.7` | MySQL **5.7.x** (EOL Oct 2023) | **3307 → 3306** | `db-data` → `/var/lib/mysql`, `./db/init` → `/docker-entrypoint-initdb.d` | charset `utf8` (utf8mb3), root password from `.env` |
| `cache` | `redis:7-alpine` | Redis 7.x | 6379 (internal only) | – | no password, no TLS, no persistence config |
| `batch` | `ledgerly/batch:1.0` ← `alpine:3.19` | busybox crond + MariaDB client | – | `reports` → `/reports` | CSV every 5 min, output to `/dev/null`, `|| true` |

## Flows

`browser → web:80 (host 8081) → api:8080 → db:3306 (JDBC, no TLS)` · `api → cache:6379 (RESP)` ·
`batch → db:3306 (mysql client) → /reports/*.csv`

## Data

| Table | Rows | Notes |
|---|---|---|
| `portfolios` | 12 | PK + unique `code` |
| `instruments` | 30 | PK + unique `symbol` |
| `positions` | 360 | derived from transactions |
| `transactions` | **200,000** | PK only – **no index on `booking_date`** (nor `portfolio_id`), dates 2024-01-01 … 2026-01-01 |

Total ≈ 15–20 MB on disk; `mysqldump` ≈ 10 MB. No routines, triggers or views.

## Configuration & secrets

| Variable | Where | Secret? |
|---|---|---|
| `MYSQL_ROOT_PASSWORD` | `.env` → db | **yes – plaintext in repo** |
| `DB_PASSWORD` | `.env` → api, batch, db (`MYSQL_PASSWORD`) | **yes – plaintext in repo** |
| `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER` | `.env` | no |
| `REDIS_HOST`, `REDIS_PORT`, `REDIS_SSL` | `.env` / compose | no (`REDIS_PASSWORD` unset) |
| `JAVA_OPTS` | baked into api image | no – but wrong (`-Xmx2g` > 1g limit) |
| `API_UPSTREAM` | compose → web | no |

## Risks (ranked)

1. **MySQL 5.7 end-of-life** – no security fixes; must move to 8.0 (utf8mb3, auth plugin, reserved words, sql_mode).
2. **Plaintext secrets** in `.env` committed to the repo; DB published on host port 3307.
3. **JVM heap > container limit** (`-Xmx2g` vs `mem_limit 1g`) → OOMKilled under load.
4. **Slow monthly report** – N+1 queries, full scans on `transactions` (no `booking_date` index).
5. **Silent batch failures** (`> /dev/null`, `|| true`) – nobody notices missing reports.
6. **Legacy runtime** – Spring Boot 2.7 (OSS support ended) on Java 11.
7. Single host, no TLS anywhere, no backups, no monitoring, no health-based restarts beyond `restart: unless-stopped`.
