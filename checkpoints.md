# Checkpoints (git tags)

Create them once on a fresh copy of the repo: `./scripts/make-checkpoints.ps1`
(or tag manually at the end of each rehearsal block: `git tag -a 03-migrated -m "..."`).
Each tag is cumulative. Jump with `git checkout <tag>`; return with `git checkout main`.

| Tag | Block (time) | Contains | Azure state expected |
|---|---|---|---|
| `00-onprem` | intro (0–8) | `docker-compose.yml`, `.env`, `web/`, `api/` (incl. dormant `azure` profile), `db/init/`, `batch/`, `cache/`, `.vscode/`, `.github/copilot-instructions.md`, `scripts/_common.ps1`, `00-prereqs.ps1`, `01-onprem-up.ps1`, README, PRESENTER-FACTS | none needed |
| `01-discovered` | discover (8–28) | + `scripts/02-discover.ps1`, `docs/inventory.md` | – |
| `02-diagrammed` | diagram (28–43) | + `docs/diagrams/ledgerly-as-is.drawio`, `ledgerly-to-be.drawio`, `ledgerly-starter.drawio`, `docs/drawio-mcp.md`, `scripts/build-drawio-library.ps1` | – |
| `03-migrated` | migrate (43–70) | + `azure.yaml`, `infra/main.bicep`, `infra/main.parameters.json`, `infra/modules/*`, `scripts/hooks/postdeploy-batch.ps1`, `scripts/03-migrate-data.ps1`, `docs/migration-plan.md` | rg provisioned, images deployed, data migrated |
| `04-modernized` | modernize (70–90) | + `scripts/04-modernize.ps1` | api on profile `azure`, no `DB_PASSWORD` |
| `05-broken` | break (90–110) | + `scripts/faults/fault-1-oom.ps1`, `fault-2-network.ps1`, `fault-3-slowquery.ps1`, `kql/queries.kql` | faults injected one at a time |
| `06-fixed` | fix (90–110) | + `scripts/faults/fix-*.ps1`, `db/migrations/001-ix-transactions-booking-date.sql`, `scripts/reset.ps1`, `scripts/cleanup.ps1`, `scripts/make-checkpoints.ps1`, everything else | all fixes applied |

Notes
- Tags capture **files**, not Azure state. Azure state is restored with `azd provision`, `scripts/reset.ps1`
  and the fix scripts.
- `docs/discovery-output.txt` (generated) is committed at `06-fixed` if it exists.
