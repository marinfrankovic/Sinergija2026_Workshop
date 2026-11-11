# cache

The cache tier is the stock `redis:7-alpine` image declared directly in
`docker-compose.yml` – no custom build, **no password, no TLS** (legacy).

In Azure it becomes **Azure Cache for Redis Basic C0** (`redis-ledgerly-workshop-<suffix>`,
TLS only on port 6380, access key stored in Key Vault as `redis-password`).
Alternative for new builds: **Azure Managed Redis** (the successor offering).
