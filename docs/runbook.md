# Runbook

## Purpose

This runbook defines how to operate, monitor, and recover the airline streaming data platform.

It is not a build guide.
It is an operations guide for an already-deployed system.

The goal is to make routine execution, failure diagnosis, and recovery repeatable without relying on memory or guesswork.

## Daily Health Checks

The daily goal is to confirm that all three layers are fresh, complete, and internally consistent.

Checks:
1. Confirm the latest workflow run completed successfully.
2. Confirm Bronze, Silver, and Gold row counts are non-zero and plausible.
3. Confirm the latest ingestion timestamp in Bronze is recent enough for expected freshness.
4. Confirm no unexpected growth in quarantine rows.
5. Confirm Gold was refreshed after Silver, not before it.

If any of these checks fail, stop and diagnose before triggering more runs.

## How to Run the Platform

The platform is run through the Databricks Workflow job `airline-dev-refresh`.

Normal execution order:
1. Bronze ingest pipeline runs
2. Silver merge pipeline runs
3. Gold refresh pipeline runs

Operator steps:
1. Open the Databricks Workflow job
2. Trigger a run
3. Confirm tasks execute in dependency order
4. Wait for all tasks to complete successfully
5. Validate freshness and row counts before treating the run as healthy

Do not run downstream pipelines manually out of order.
The workflow is the operational entry point because it preserves dependency sequencing and failure gating.

## Failure Modes

Common failure modes in this platform include:

1. Authentication failure
   - broken or expired secret
   - incorrect Key Vault access
   - Event Hubs auth misconfiguration

2. Upstream data quality failure
   - malformed events
   - missing required fields
   - unexpected null growth in quarantine

3. Schema drift
   - new upstream field
   - renamed field
   - type change that breaks downstream assumptions

4. Pipeline execution failure
   - Bronze, Silver, or Gold pipeline errors
   - workflow task failure
   - retry loops that extend incident duration

5. Data freshness failure
   - workflow succeeds but no new data arrives
   - late data not yet processed
   - downstream layers lag behind upstream completion

## Recovery Actions

Recovery depends on the failure mode.

1. Authentication failure
   - verify the secret value in Key Vault
   - verify Databricks can still read the secret scope
   - restore the correct secret if it was changed
   - rerun the workflow after confirming access

2. Data quality failure
   - inspect quarantine rows
   - identify whether the issue is malformed payload or missing required fields
   - correct the upstream producer if needed
   - rerun the workflow only after understanding the failure pattern

3. Schema drift
   - compare Bronze schema to Silver contract
   - decide whether the change is additive or breaking
   - update downstream logic intentionally
   - rerun affected layers in dependency order

4. Pipeline execution failure
   - inspect the failed task logs
   - identify the exact failing layer
   - fix the root cause before rerunning
   - do not rerun blindly into repeated failure

5. Freshness failure
   - confirm whether new data actually arrived upstream
   - confirm Bronze advanced
   - only then rerun downstream layers if needed

## Secret Rotation

Secret rotation must be treated as a controlled operational change.

Steps:
1. Generate or retrieve the new secret value from the upstream system.
2. Update the secret in Azure Key Vault.
3. Confirm Databricks secret scope can still read the updated value.
4. Trigger a controlled workflow run.
5. Verify Bronze ingestion succeeds before treating the rotation as complete.

If a secret is exposed or pasted into an unsafe location, rotate it immediately and treat the event as a security incident.
Do not leave known-exposed credentials active.