# Schema Drift Runbook

## Scenario

A producer starts sending a new field called `YEAR` that was not present in the original event schema.

This is an additive schema drift event:
- existing columns are unchanged
- one new column appears in incoming events
- Bronze may capture it, but Silver and Gold will ignore it until explicitly updated

The operational question is not "is the data bad?"
The question is "how does the platform detect and safely absorb a contract change without corrupting downstream layers?"

## Expected Bronze Behavior

Bronze is the append-only capture layer, so its job is to preserve the incoming payload as faithfully as possible.

For an additive schema drift event like a new `YEAR` field:
- Bronze should continue ingesting events without dropping existing columns
- the new field should become visible at the raw capture layer
- no historical rows need to be rewritten
- Bronze remains the source of truth for replay and downstream recovery

If Bronze cannot capture the new field, the platform loses the earliest point where the drift became visible, which makes debugging and replay harder.

## Expected Silver/Gold Behavior

Silver and Gold are contract layers, not raw capture layers.

For an additive schema drift event like a new `YEAR` field:
- Silver continues to process the existing selected columns
- the new column is ignored until explicitly added to the transformation logic
- Gold continues to build from Silver without seeing the new field

This means additive drift can remain invisible to downstream consumers unless there is explicit schema comparison or monitoring between layers.

That behavior is safe in the short term, but dangerous if the new column is semantically important and silently excluded from downstream models.

## Detection

Schema drift should be detected by comparing the effective schema at Bronze with the expected schema used by Silver.

For an additive change like `YEAR`:
- Bronze exposes the new field first
- Silver continues using its fixed select list and will not include it
- this creates a schema mismatch between layers

The correct detection pattern is:
1. capture Bronze schema regularly
2. compare it to the Silver input contract
3. alert when new fields appear upstream but are not represented downstream

Without this check, additive drift becomes silent drift.

## Recovery

Recovery depends on the type of schema drift.

For an additive change like `YEAR`:
1. confirm Bronze is capturing the new field
2. decide whether the field matters for downstream business logic
3. if yes, add the field explicitly to Silver transformations
4. propagate it into Gold only if it belongs in business-facing marts
5. rerun the affected pipelines so downstream layers rebuild with the updated contract

No full refresh is required for a simple additive field if the existing logic remains valid.

For a breaking change such as a rename or type change:
- stop downstream propagation
- update transformation logic
- validate compatibility
- then rerun the affected layers in a controlled order

## Operational Principle

Additive drift is usually a controlled extension of the contract.
Breaking drift is a contract violation.

The platform should tolerate additive changes at Bronze, detect schema mismatch between Bronze and Silver, and only propagate new fields downstream when they are intentionally added to the contract.

This keeps Bronze flexible and Silver/Gold stable.