"""
Airline Event Hub Producer (AAD-only, no SAS keys)
Reads CSV → JSON events → batch send to Event Hub
Auth: DefaultAzureCredential (Azure CLI locally, Managed Identity in prod)
"""

import csv
import json
import sys
import time
from pathlib import Path

from azure.identity import DefaultAzureCredential
from azure.eventhub import EventHubProducerClient, EventData

# ── Config (no secrets) ──────────────────────────────────────────────
FULLY_QUALIFIED_NAMESPACE = "ehns-airline-dlt-dev-uks.servicebus.windows.net"
EVENTHUB_NAME = "airline-events"
CSV_PATH = r"C:\Users\Faisal\Projects\Creating Delta Live Tables in Databricks\Project Data\Data\Data\ONTIME_REPORTING_021.csv"


def read_csv_as_dicts(path: str):
    """Yield each CSV row as a dict. Handles missing/empty fields."""
    with open(path, "r") as f:
        reader = csv.DictReader(f)
        for row_num, row in enumerate(reader, start=2):  # 2 because header is row 1
            row["_row_num"] = row_num  # lineage: trace back to source row
            yield row


def send_events(csv_path: str):
    """Batch-send CSV rows to Event Hub using AAD auth."""

    credential = DefaultAzureCredential()

    client = EventHubProducerClient(
        fully_qualified_namespace=FULLY_QUALIFIED_NAMESPACE,
        eventhub_name=EVENTHUB_NAME,
        credential=credential,
    )

    sent = 0
    failed = 0

    with client:
        batch = client.create_batch()

        for row in read_csv_as_dicts(csv_path):
            event_body = json.dumps(row)

            try:
                batch.add(EventData(event_body))
            except ValueError:
                # Batch is full — send it and start a new one
                client.send_batch(batch)
                sent += batch.size_in_bytes  # tracking
                batch = client.create_batch()
                batch.add(EventData(event_body))
            except Exception as e:
                # Single event too large or malformed — skip, log, continue
                failed += 1
                print(f"SKIP row {row.get('_row_num', '?')}: {e}", file=sys.stderr)
                continue

        # Send remaining events in the last batch
        if batch:
            client.send_batch(batch)

    print(f"Done. Failed rows: {failed}")


if __name__ == "__main__":
    send_events(CSV_PATH)