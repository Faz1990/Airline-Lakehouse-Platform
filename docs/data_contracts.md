# Data Contracts

## Bronze Contract

Bronze is the append-only source-of-truth capture layer.

Guarantees:
- raw flight events are ingested from Event Hubs without business transformation
- Event Hubs lineage is preserved through `eh_enqueued_time`, `eh_offset`, and `eh_partition_id`
- ingestion timestamp is recorded as `ingest_ts`
- malformed or incomplete records may still appear here because Bronze prioritizes capture over business correctness

Non-guarantees:
- no deduplication
- no business-friendly typing
- no consumer-facing stability for analytics

Operational purpose:
Bronze exists to preserve replayability, auditability, and the earliest visible form of upstream change.

## Silver Contract

## Silver Contract

Silver is the cleaned, typed, deduplicated contract layer.

Guarantees:
- required fields used for downstream logic are present
- data types are explicitly cast for analytical use
- duplicate flight events are resolved through MERGE logic using the business key
- the latest version of a flight record wins according to `eh_enqueued_time`
- Silver is stable enough to support Gold marts and business-facing queries

Non-guarantees:
- Silver does not preserve every raw upstream variation
- Silver is not the place for full historical replay or forensic debugging
- Silver may ignore additive upstream fields until they are intentionally added to the contract

Operational purpose:
Silver exists to create a trustworthy, reusable business-level table from raw Bronze data while preserving idempotency and downstream stability.
bronze

## Gold Contract

Gold is the business-facing analytics contract layer.

Guarantees:
- data is organized into marts that are easier to query than raw operational tables
- facts and dimensions reflect cleaned Silver inputs, not raw upstream events
- Gold is suitable for reporting, KPI analysis, and interview-style SQL queries
- Gold refreshes only after upstream Silver processing is complete

Non-guarantees:
- Gold is not the source of truth for replay or debugging
- Gold does not preserve raw event-level lineage in the same way Bronze does
- Gold may be rebuilt from Silver and should be treated as a consumption layer, not a capture layer

Operational purpose:
Gold exists to provide stable, business-readable tables for analysis while keeping ingestion and cleaning concerns out of downstream reporting workflows.

## Expectations

The platform currently enforces three Bronze validation expectations on the validated path:

1. `MONTH IS NOT NULL`
2. `ORIGIN IS NOT NULL`
3. `DEST IS NOT NULL`

Operational meaning:
- records that meet these expectations continue into `events_bronze_valid`
- records that fail them are excluded from the valid path
- the same failed records are captured in `events_quarantine` for inspection and recovery

These expectations are not business analytics rules.
They are minimum structural checks that protect downstream processing from obviously incomplete records.

## Quarantine Reason Codes

The current quarantine path captures records that fail minimum Bronze validation.

Current reason code:
- `Failed bronze validation: null MONTH, ORIGIN, or DEST`

Meaning:
- the record was ingested into Bronze
- it did not satisfy the minimum structural checks for the validated Bronze path
- it was routed to quarantine for inspection instead of being silently lost

This reason code is intentionally simple for the current project stage.
In a more mature platform, reason codes would become more granular so operators could distinguish parse failure, missing required field, type mismatch, and contract drift.

## SLA Assumptions

This project uses development-scale SLA assumptions, not production guarantees.

Current assumptions:
- Bronze, Silver, and Gold are refreshed through the Databricks workflow in dependency order
- Gold should only be considered fresh after Bronze and Silver complete successfully
- freshness is judged by recent ingestion and successful workflow completion, not by continuous streaming guarantees
- late-arriving data is allowed and should propagate through the same workflow path
- manual triggering is acceptable in dev, but production would require a scheduled or event-driven refresh policy

These assumptions define expected behavior for a learning and portfolio environment.
They are not equivalent to formal production SLAs with uptime, latency, and alerting commitments.