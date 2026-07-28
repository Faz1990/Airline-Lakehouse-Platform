# Databricks notebook source
# MAGIC %md
# MAGIC # Gold — dimensional marts
# MAGIC Pipeline: `airline-dlt-gold` | Catalog: `airline_dev` | Schema: `gold` | Edition: ADVANCED | Serverless | Triggered
# MAGIC
# MAGIC All tables are **batch** reads from Silver (`spark.read.table`, not streaming): Gold is a materialised
# MAGIC snapshot rebuilt from Silver's current state on each trigger.
# MAGIC
# MAGIC Star schema: `fact_flights` + `dim_carrier`, `dim_airport`, `dim_date`.

# COMMAND ----------

import dlt
from pyspark.sql.functions import col, current_timestamp

# COMMAND ----------

@dlt.table(name="fact_flights", comment="Fact: flight-level measures")
def fact_flights():
    return (
        spark.read.table("airline_dev.silver.flights_clean")
        .select(
            col("OP_UNIQUE_CARRIER").alias("carrier_code"),
            col("ORIGIN").alias("origin_code"),
            col("DEST").alias("dest_code"),
            col("month"),
            col("day_of_month"),
            col("day_of_week"),
            col("flight_num"),
            col("scheduled_dep_time"),
            col("dep_delay_minutes"),
            col("arr_delay_minutes"),
            col("dep_delayed_15min"),
            col("cancelled"),
            col("distance_miles"),
            col("actual_elapsed_minutes"),
            col("scheduled_elapsed_minutes"),
            col("carrier_delay_minutes"),
            col("weather_delay_minutes"),
            col("nas_delay_minutes"),
            col("security_delay_minutes"),
            col("late_aircraft_delay_minutes"),
            col("silver_processed_ts"),
            current_timestamp().alias("gold_processed_ts")
        )
    )

# COMMAND ----------

@dlt.table(name="dim_carrier", comment="Dimension: airline carriers")
def dim_carrier():
    return (
        spark.read.table("airline_dev.silver.flights_clean")
        .select("OP_UNIQUE_CARRIER")
        .distinct()
        .withColumnRenamed("OP_UNIQUE_CARRIER", "carrier_code")
        .withColumn("gold_processed_ts", current_timestamp())
    )

# COMMAND ----------

@dlt.table(name="dim_airport", comment="Dimension: airports")
def dim_airport():
    origins = spark.read.table("airline_dev.silver.flights_clean").select(
        col("ORIGIN").alias("airport_code"),
        col("origin_airport_id").alias("airport_id"),
        col("origin_city").alias("city")
    )
    dests = spark.read.table("airline_dev.silver.flights_clean").select(
        col("DEST").alias("airport_code"),
        col("dest_airport_id").alias("airport_id"),
        col("dest_city").alias("city")
    )
    return origins.union(dests).distinct().withColumn("gold_processed_ts", current_timestamp())

# COMMAND ----------

@dlt.table(name="dim_date", comment="Dimension: date")
def dim_date():
    return (
        spark.read.table("airline_dev.silver.flights_clean")
        .select("month", "day_of_month", "day_of_week")
        .distinct()
        .withColumn("gold_processed_ts", current_timestamp())
    )
