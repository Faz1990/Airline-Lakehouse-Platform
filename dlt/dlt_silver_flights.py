# Databricks notebook source
# MAGIC %md
# MAGIC # Silver — typed, deduplicated flights
# MAGIC Pipeline: `airline-dlt-silver` (ID bc99e9b9-faea-46e0-8789-3265b2ab8c91) | Catalog: `airline_dev` | Schema: `silver` | Edition: ADVANCED | Serverless | Triggered
# MAGIC
# MAGIC Reads the Bronze Delta table directly (`spark.readStream.table`), not `dlt.read_stream` — separate pipeline, independent blast radius.
# MAGIC
# MAGIC **Proven:** Bronze valid 1,858 → Silver 1,244 (614 duplicates merged). Idempotent re-run: 0 new records.

# COMMAND ----------

import dlt
from pyspark.sql.functions import col, when, current_timestamp
from pyspark.sql.types import IntegerType, FloatType

# COMMAND ----------

@dlt.view(
    name="bronze_stream",
    comment="Reads validated Bronze and casts types for Silver"
)
def bronze_stream():
    return (
        spark.readStream
        .table("airline_dev.bronze.events_bronze_valid")
        .select(
            # Business key columns
            col("OP_UNIQUE_CARRIER"),
            col("OP_CARRIER_FL_NUM").cast(IntegerType()).alias("flight_num"),
            col("ORIGIN"),
            col("DEST"),
            col("MONTH").cast(IntegerType()).alias("month"),
            col("DAY_OF_MONTH").cast(IntegerType()).alias("day_of_month"),
            col("CRS_DEP_TIME").cast(IntegerType()).alias("scheduled_dep_time"),

            # Date/time measures
            col("DAY_OF_WEEK").cast(IntegerType()).alias("day_of_week"),
            col("DEP_TIME").cast(FloatType()).alias("actual_dep_time"),
            col("ARR_TIME").cast(FloatType()).alias("actual_arr_time"),
            col("CRS_ARR_TIME").cast(IntegerType()).alias("scheduled_arr_time"),

            # Delay measures
            col("DEP_DELAY_NEW").cast(FloatType()).alias("dep_delay_minutes"),
            col("DEP_DEL15").cast(FloatType()).alias("dep_delayed_15min"),
            col("ARR_DELAY_NEW").cast(FloatType()).alias("arr_delay_minutes"),

            # Flight details
            col("TAIL_NUM").alias("tail_num"),
            col("ORIGIN_AIRPORT_ID").cast(IntegerType()).alias("origin_airport_id"),
            col("ORIGIN_CITY_NAME").alias("origin_city"),
            col("DEST_AIRPORT_ID").cast(IntegerType()).alias("dest_airport_id"),
            col("DEST_CITY_NAME").alias("dest_city"),
            col("DEP_TIME_BLK").alias("dep_time_block"),
            col("ARR_TIME_BLK").alias("arr_time_block"),

            # Cancellation
            col("CANCELLED").cast(FloatType()).alias("cancelled"),
            col("CANCELLATION_CODE").alias("cancellation_code"),

            # Duration & distance
            col("CRS_ELAPSED_TIME").cast(FloatType()).alias("scheduled_elapsed_minutes"),
            col("ACTUAL_ELAPSED_TIME").cast(FloatType()).alias("actual_elapsed_minutes"),
            col("DISTANCE").cast(FloatType()).alias("distance_miles"),
            col("DISTANCE_GROUP").cast(IntegerType()).alias("distance_group"),

            # Delay breakdown
            col("CARRIER_DELAY").cast(FloatType()).alias("carrier_delay_minutes"),
            col("WEATHER_DELAY").cast(FloatType()).alias("weather_delay_minutes"),
            col("NAS_DELAY").cast(FloatType()).alias("nas_delay_minutes"),
            col("SECURITY_DELAY").cast(FloatType()).alias("security_delay_minutes"),
            col("LATE_AIRCRAFT_DELAY").cast(FloatType()).alias("late_aircraft_delay_minutes"),

            # Lineage
            col("_row_num"),
            col("eh_enqueued_time"),
            col("ingest_ts").alias("bronze_ingest_ts"),
            current_timestamp().alias("silver_processed_ts")
        )
    )

# COMMAND ----------

# 7-column composite business key: scheduled/planned attributes only, never observed values.
# Actual values change — that's what we're measuring, so they cannot identify the record.
dlt.create_streaming_table(
    name="flights_clean",
    comment="Silver: deduplicated flights, typed columns, SCD Type 1",
    table_properties={"quality": "silver"}
)

dlt.apply_changes(
    target="flights_clean",
    source="bronze_stream",
    keys=["OP_UNIQUE_CARRIER", "flight_num", "ORIGIN", "DEST", "month", "day_of_month", "scheduled_dep_time"],
    sequence_by=col("eh_enqueued_time"),
    stored_as_scd_type=1
)
