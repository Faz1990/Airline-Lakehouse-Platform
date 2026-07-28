# Databricks notebook source
# MAGIC %md
# MAGIC # Bronze — Event Hubs ingestion via Kafka protocol
# MAGIC Pipeline: `airline-dlt-bronze-silver` | Catalog: `airline_dev` | Schema: `bronze` | Edition: ADVANCED | Serverless | Triggered
# MAGIC
# MAGIC Tables: `events_raw` (append-only), `events_bronze_valid` (expectations), `events_quarantine` (dead-letter)

# COMMAND ----------

import dlt
import json
from pyspark.sql.functions import col, from_json, current_timestamp, lit
from pyspark.sql.types import *

eh_connection_string = dbutils.secrets.get(scope="airline-kv-scope", key="eh-connection-string")
eh_name = "airline-events"
eh_namespace = "ehns-airline-dlt-dev-uks"

kafka_conf = {
    "kafka.bootstrap.servers": f"{eh_namespace}.servicebus.windows.net:9093",
    "kafka.security.protocol": "SASL_SSL",
    "kafka.sasl.mechanism": "PLAIN",
    "kafka.sasl.jaas.config": f'kafkashaded.org.apache.kafka.common.security.plain.PlainLoginModule required username="$ConnectionString" password="{eh_connection_string};EntityPath={eh_name}";',
    "subscribe": eh_name,
    "startingOffsets": "earliest",
    "kafka.request.timeout.ms": "120000",
    "kafka.session.timeout.ms": "60000"
}

# COMMAND ----------

# All fields land as StringType at Bronze: raw fidelity first, casting happens at Silver.
airline_schema = StructType([
    StructField("MONTH", StringType()),
    StructField("DAY_OF_MONTH", StringType()),
    StructField("DAY_OF_WEEK", StringType()),
    StructField("OP_UNIQUE_CARRIER", StringType()),
    StructField("TAIL_NUM", StringType()),
    StructField("OP_CARRIER_FL_NUM", StringType()),
    StructField("ORIGIN_AIRPORT_ID", StringType()),
    StructField("ORIGIN", StringType()),
    StructField("ORIGIN_CITY_NAME", StringType()),
    StructField("DEST_AIRPORT_ID", StringType()),
    StructField("DEST", StringType()),
    StructField("DEST_CITY_NAME", StringType()),
    StructField("CRS_DEP_TIME", StringType()),
    StructField("DEP_TIME", StringType()),
    StructField("DEP_DELAY_NEW", StringType()),
    StructField("DEP_DEL15", StringType()),
    StructField("DEP_TIME_BLK", StringType()),
    StructField("CRS_ARR_TIME", StringType()),
    StructField("ARR_TIME", StringType()),
    StructField("ARR_DELAY_NEW", StringType()),
    StructField("ARR_TIME_BLK", StringType()),
    StructField("CANCELLED", StringType()),
    StructField("CANCELLATION_CODE", StringType()),
    StructField("CRS_ELAPSED_TIME", StringType()),
    StructField("ACTUAL_ELAPSED_TIME", StringType()),
    StructField("DISTANCE", StringType()),
    StructField("DISTANCE_GROUP", StringType()),
    StructField("CARRIER_DELAY", StringType()),
    StructField("WEATHER_DELAY", StringType()),
    StructField("NAS_DELAY", StringType()),
    StructField("SECURITY_DELAY", StringType()),
    StructField("LATE_AIRCRAFT_DELAY", StringType()),
    StructField("_row_num", StringType())
])

# COMMAND ----------

@dlt.table(
    name="events_raw",
    comment="Bronze: raw events from Event Hubs via Kafka protocol, append-only",
    table_properties={"quality": "bronze"}
)
def events_raw():
    raw_stream = (
        spark.readStream
        .format("kafka")
        .options(**kafka_conf)
        .load()
    )
    return (
        raw_stream
        .select(
            col("timestamp").alias("eh_enqueued_time"),
            col("offset").alias("eh_offset"),
            col("partition").alias("eh_partition_id"),
            from_json(col("value").cast("string"), airline_schema).alias("payload"),
            current_timestamp().alias("ingest_ts")
        )
        .select(
            "eh_enqueued_time", "eh_offset", "eh_partition_id",
            "payload.*", "ingest_ts"
        )
    )

# COMMAND ----------

@dlt.table(
    name="events_bronze_valid",
    comment="Bronze validated: passed basic quality checks",
    table_properties={"quality": "bronze_validated"}
)
@dlt.expect_or_drop("valid_month", "MONTH IS NOT NULL")
@dlt.expect_or_drop("valid_origin", "ORIGIN IS NOT NULL")
@dlt.expect_or_drop("valid_dest", "DEST IS NOT NULL")
def events_bronze_valid():
    return dlt.read_stream("events_raw")


@dlt.table(
    name="events_quarantine",
    comment="Quarantine: rows failing bronze expectations",
    table_properties={"quality": "quarantine"}
)
def events_quarantine():
    return (
        dlt.read_stream("events_raw")
        .filter(
            col("MONTH").isNull() |
            col("ORIGIN").isNull() |
            col("DEST").isNull()
        )
        .withColumn("quarantine_reason",
            lit("Failed bronze validation: null MONTH, ORIGIN, or DEST"))
        .withColumn("quarantine_ts", current_timestamp())
    )
