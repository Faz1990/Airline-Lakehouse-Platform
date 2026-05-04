# Postmortem: Induced Key Vault Secret Failure

**Date:** 2026-04-22  
**Author:** Faisal Ahmed  
**Severity:** P2 (simulated production incident)  
**Duration:** 2h 12m (8:18 PM — 10:30 PM BST)

## Summary
Deliberately induced an authentication failure by replacing the Event Hub connection string in Key Vault with an invalid value. Pipeline workflow `airline-dev-refresh` failed as expected. Recovery took 1m 56s after secret restoration.

## Impact
- No data loss (Bronze is append-only, no partial writes)
- No Silver/Gold corruption (MERGE didn't run, existing data preserved)
- Pipeline unavailable during incident window
- Zero customer impact (dev environment)

## Timeline
| Time | Event |
|------|-------|
| 20:18 | Key Vault secret overwritten with invalid value |
| 20:18 | Workflow triggered, bronze_ingest task started |
| 20:18–22:24 | Pipeline stuck in retry loops (2h 6m) |
| 22:24 | Run manually canceled |
| 22:28 | Valid connection string retrieved from Event Hub authorization rule |
| 22:29 | Key Vault secret restored |
| 22:30 | Workflow re-triggered, full pipeline succeeded in 1m 56s |

## Root Cause
Primary: Invalid secret in Key Vault caused Kafka authentication to fail during `describeTopics` call.

Secondary (operational): Retry policy allowed the failure to persist far longer than necessary. Kafka connection timeouts (120s request, 60s session) multiplied by retries stretched a 2-minute diagnosis into a 2-hour incident.

## Detection
Manual detection via workflow run page. No automated alert fired.

## Resolution
1. Canceled stuck run via UI
2. Retrieved valid connection string: `az eventhubs namespace authorization-rule keys list`
3. Restored Key Vault secret: `az keyvault secret set`
4. Re-triggered workflow — succeeded in 1m 56s, no data loss

## What Went Well
- Bronze's append-only design prevented any write attempt with bad data
- MERGE idempotency meant Silver and Gold data was safe
- `{{secrets/...}}` indirection meant zero code changes needed to recover — just a Key Vault update
- Recovery was a single CLI command

## What Went Wrong
- No automated failure alert
- Retry policy too permissive for auth failures — retries can't fix a bad secret
- No task-level timeout to fail fast

## Action Items
1. **Reduce retries for auth failures** — set retries to 0 or 1 for pipeline tasks (current: 1, still too long given Kafka timeouts)
2. **Add task-level timeout** — set max 10 minutes per pipeline task; auth failures should fail fast
3. **Configure failure notifications** — email alert on first task failure, not after full retry exhaustion
4. **Runbook entry** — document the recovery steps (connection string retrieval + Key Vault update) in `/docs/runbook.md`
5. **Monitor Key Vault access** — enable diagnostic logs to detect secret modifications

## Transferable Principles
- **Identity-first architecture pays off under failure.** Only the secret changed — no code, no infrastructure, no pipeline definition. Recovery was a single CLI command.
- **Retries can't fix configuration errors.** Design timeouts around the expected failure mode, not the happy path.
- **Append-only and idempotent design limits blast radius.** Bad auth → no writes → no corruption → no rollback needed.

## Evidence
- `phase7_induced_failure_workflow.png` — failed run (2h 6m 56s, UserCanceled)
- `phase7_recovery_success.png` — successful recovery (1m 56s)
- `phase7_incident_timeline.png` — full run history showing failure and recovery