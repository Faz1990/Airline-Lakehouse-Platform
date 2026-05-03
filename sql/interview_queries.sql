-- ============================================================
-- AIRLINE DLT PROJECT — INTERVIEW SQL PACK
-- Author: Faisal Ahmed
-- Source: airline_dev.gold.* (Gold marts on top of Silver/Bronze pipeline)
-- Total flights in dataset: 1,770 (single carrier: AA)
-- ============================================================


-- ============================================================
-- Query 1: Top 5 carriers by average departure delay
-- ============================================================
-- Business question: Which 5 airlines have the worst average 
--   departure delays? Exclude cancelled flights.
-- Tables: airline_dev.gold.fact_flights
-- Note: Dataset contains only one carrier (AA), so query returns
--   1 row. Logic is production-ready for multi-carrier data.
-- ============================================================
SELECT 
    carrier_code,
    ROUND(AVG(dep_delay_minutes), 2) AS avg_delay_minutes,
    COUNT(*) AS total_flights
FROM airline_dev.gold.fact_flights
WHERE cancelled = 0
GROUP BY carrier_code
ORDER BY avg_delay_minutes DESC
LIMIT 5;

-- Result: AA | 13.18 | 1,719

-- ============================================================
-- Query 2: Top 10 routes by flight volume
-- ============================================================
-- Business question: Which origin-destination pairs have the 
--   most flights? Show the top 10.
-- Tables: airline_dev.gold.fact_flights
-- Note: Bidirectional routes (e.g., LAX-JFK and JFK-LAX) appear
--   separately because they are operationally distinct.
-- ============================================================
SELECT 
    CONCAT(origin_code, '-', dest_code) AS route,
    COUNT(*) AS flight_count
FROM airline_dev.gold.fact_flights
GROUP BY origin_code, dest_code
ORDER BY flight_count DESC
LIMIT 10;

-- Top result: LAX-JFK | 181 flights

-- ============================================================
-- Query 3: Day-of-week delay pattern
-- ============================================================
-- Business question: Which day of the week has the worst average 
--   departure delay? Show all 7 days ranked from worst to best.
-- Tables: airline_dev.gold.fact_flights
-- Note: BTS convention (1=Monday, 7=Sunday). Excludes cancelled
--   flights from the average to avoid skew from null delay values.
-- Finding: Tuesday is worst (18.06 min), Monday is best (9.79 min).
--   Counterintuitive — common wisdom says Monday is worst for
--   business travel, but this dataset shows the opposite.
-- ============================================================
SELECT 
    day_of_week,
    CASE day_of_week
        WHEN 1 THEN 'Monday'
        WHEN 2 THEN 'Tuesday'
        WHEN 3 THEN 'Wednesday'
        WHEN 4 THEN 'Thursday'
        WHEN 5 THEN 'Friday'
        WHEN 6 THEN 'Saturday'
        WHEN 7 THEN 'Sunday'
        ELSE 'Unknown'
    END AS day_name,
    ROUND(AVG(dep_delay_minutes), 2) AS avg_dep_delay_minutes,
    COUNT(*) AS flight_count
FROM airline_dev.gold.fact_flights
WHERE cancelled = 0
GROUP BY day_of_week
ORDER BY avg_dep_delay_minutes DESC;

-- ============================================================
-- Query 4: Routes with highest cancellation rate
-- ============================================================
-- Business question: Which routes have the worst cancellation 
--   rates? Filter to routes with at least 20 flights to avoid
--   noise from rare routes.
-- Tables: airline_dev.gold.fact_flights
-- Concepts demonstrated:
--   - COUNT_IF for conditional counting (Databricks/Spark dialect)
--   - HAVING vs WHERE: HAVING filters aggregates, WHERE filters rows
--   - Integer division pitfall: multiply by 100.0 to force double 
--     arithmetic and prevent silent truncation to zero
-- Finding: LAX-JFK has the highest cancellation rate at 16.57% 
--   (30 of 181 flights). Worth investigating — could indicate 
--   weather (Northeast hub), congestion, or operational issues
--   on this transcontinental route.
-- ============================================================
SELECT  
    CONCAT(origin_code, '-', dest_code) AS route,
    COUNT(*) AS total_flights,
    COUNT_IF(cancelled = 1) AS cancelled_flights,
    ROUND(COUNT_IF(cancelled = 1) * 100.0 / COUNT(*), 2) AS cancellation_rate_pct
FROM airline_dev.gold.fact_flights
GROUP BY origin_code, dest_code
HAVING COUNT(*) >= 20
ORDER BY cancellation_rate_pct DESC
LIMIT 10;

-- ============================================================
-- Query 5: Cumulative flights and rolling cancellation rate per route
-- ============================================================
-- Business question: For top routes, show daily flight counts plus
--   running cumulative totals and a rolling cancellation rate.
--   Useful for identifying whether problems concentrate early or 
--   late in the period.
-- Tables: airline_dev.gold.fact_flights
-- Concepts demonstrated:
--   - CTE for staged aggregation (collapse rows before windowing)
--   - Window function with PARTITION BY (resets per route)
--   - Running total frame: ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
--   - Named WINDOW clause (DRY: define once, reference 3x)
--   - Combined window expressions for derived metrics 
--     (rolling rate = SUM(cancelled)/SUM(flights))
-- Findings:
--   - JFK-LAX builds steadily through month, low cancellations
--   - LAX-JFK shows higher cancellation pattern (16.57% overall, see Q4)
--   - Data quality gap detected: at least one row has null day_of_month
--     -> add expectation in Bronze layer (follow-up)
-- ============================================================
WITH daily_route_flights AS (
    SELECT
        CONCAT(origin_code, '-', dest_code) AS route,
        day_of_month,
        COUNT(*) AS daily_flights,
        COUNT_IF(cancelled = 1) AS daily_cancelled
    FROM airline_dev.gold.fact_flights
    GROUP BY origin_code, dest_code, day_of_month
)
SELECT
    route,
    day_of_month,
    daily_flights,
    daily_cancelled,
    SUM(daily_flights) OVER w AS cumulative_flights,
    SUM(daily_cancelled) OVER w AS cumulative_cancelled,
    ROUND(SUM(daily_cancelled) OVER w * 100.0 / SUM(daily_flights) OVER w, 2) AS rolling_cancellation_rate_pct
FROM daily_route_flights
WHERE route IN ('LAX-JFK', 'JFK-LAX', 'LGA-ORD')
WINDOW w AS (
    PARTITION BY route
    ORDER BY day_of_month
    ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
)
ORDER BY route, day_of_month;

-- ============================================================
-- Query 6: Delay attribution breakdown
-- ============================================================
-- Business question: For flights delayed 15+ minutes, what's
--   the breakdown of delay causes? Show total minutes per type
--   and percent of total delay attributed to each.
-- Tables: airline_dev.gold.fact_flights
-- Concepts demonstrated:
--   - LATERAL VIEW + STACK for unpivoting wide -> long format
--   - CTE to separate unpivot logic from aggregation
--   - Empty OVER() window function for "% of grand total" pattern
--     (computes denominator across all groups in single pass)
-- BTS context: Cause attribution columns are only populated for 
--   delays >= 15 min; null/zero otherwise. Filter required.
-- Findings: 
--   - Carrier-controllable delays (carrier + late_aircraft) = 77.3%
--     of attributed delay minutes. Late aircraft is upstream
--     carrier issues cascading, so airline operations dominate.
--   - NAS (ATC/airspace) = 18.2%. External infrastructure factor.
--   - Weather = 4.4% — low because severe weather usually triggers
--     cancellation, not delay. Cancelled flights are excluded
--     from this rollup.
--   - Security ~ 0%. Rarely a flight-delay driver at scale.
-- ============================================================
WITH delays_unpivoted AS (
    SELECT delay_type, minutes
    FROM airline_dev.gold.fact_flights
    LATERAL VIEW stack(5,
        'carrier',       carrier_delay_minutes,
        'weather',       weather_delay_minutes,
        'nas',           nas_delay_minutes,
        'security',      security_delay_minutes,
        'late_aircraft', late_aircraft_delay_minutes
    ) AS delay_type, minutes
    WHERE dep_delay_minutes >= 15
      AND minutes IS NOT NULL
      AND minutes > 0
)
SELECT 
    delay_type,
    SUM(minutes) AS total_delay_minutes,
    ROUND(SUM(minutes) * 100.0 / SUM(SUM(minutes)) OVER (), 2) AS pct_of_total_delay
FROM delays_unpivoted
GROUP BY delay_type
ORDER BY total_delay_minutes DESC;

-- ============================================================
-- Query 7: Top 3 most delayed flights per route
-- ============================================================
-- Business question: For each route, identify the 3 most 
--   delayed flights. Useful for spotting recurring problem
--   flights vs one-off bad days.
-- Tables: airline_dev.gold.fact_flights
-- Concepts demonstrated:
--   - DENSE_RANK() window function
--   - "Top N per group" pattern via CTE + outer WHERE
--   - PARTITION BY for resetting rank per group
--   - Why aliases can't be used in window definitions
--     (CONCAT repeated because 'route' alias not yet visible)
-- Why not LIMIT 3?
--   LIMIT chops the final result globally — would return top 3 
--   flights across ALL routes combined, missing the worst delays 
--   in smaller routes. PARTITION BY route + WHERE rank <= 3 
--   returns top 3 within EACH group. Top-N-per-group is the 
--   most common SQL interview pattern after JOIN.
-- Why DENSE_RANK over RANK or ROW_NUMBER?
--   ROW_NUMBER: arbitrary tie-breaking (could pick wrong row)
--   RANK: leaves gaps after ties (1,2,2,4) - confusing in output
--   DENSE_RANK: ties share rank, no gaps (1,2,2,3) - cleanest
--     for "top N tiers" semantics where ties should appear together
-- Findings:
--   - 270 rows returned (~90 routes × 3 ranks each)
--   - DENSE_RANK working: tied delays produce shared ranks
--     e.g. BOS-DFW had two flights tied at 5 min delay (both rank 2)
-- ============================================================
WITH ranked AS (
    SELECT
        CONCAT(origin_code, '-', dest_code) AS route,
        day_of_month,
        flight_num,
        dep_delay_minutes,
        DENSE_RANK() OVER (
            PARTITION BY CONCAT(origin_code, '-', dest_code) 
            ORDER BY dep_delay_minutes DESC
        ) AS delay_rank
    FROM airline_dev.gold.fact_flights
    WHERE cancelled = 0
      AND dep_delay_minutes IS NOT NULL
)
SELECT *
FROM ranked
WHERE delay_rank <= 3
ORDER BY route, delay_rank;

-- ============================================================
-- Query 8: Day-over-day delay change per route (LAG)
-- ============================================================
-- Business question: For each route, show daily average delay
--   alongside the previous day's average. Calculate day-over-day
--   change. Which routes had the biggest single-day worsening?
-- Tables: airline_dev.gold.fact_flights
-- Concepts demonstrated:
--   - LAG() window function (access previous row's value)
--   - LAG vs self-join: same logic, single pass, no shuffle
--   - QUALIFY clause: filter on window results without extra CTE
--     (Databricks/Snowflake/BigQuery; not standard ANSI SQL)
--   - Two-stage aggregation pattern: GROUP BY in CTE, then window
--     functions in outer SELECT
-- LAG semantic limitation:
--   LAG operates on row order, NOT calendar order. If a route
--   skips days (no flights), LAG returns the previous *row* in
--   the partition, not the previous *day*. For true daily 
--   comparisons in production, JOIN against a date dimension 
--   table to fill missing days with NULL or 0.
-- Findings:
--   - OGG-DFW shows +1090 min change on day 5: outlier flight
--     delayed 18 hours, plus a gap before day 5 (no flights 
--     prior). Skews average dramatically.
--   - MSP-ORD jumped 12 -> 467 min average — single bad day
--     warrants operational investigation
--   - Pattern: largest jumps come from low-volume routes where
--     one bad flight dominates the daily mean. Consider 
--     filtering by minimum flights per day in production.
-- ============================================================
WITH daily_delays AS (
    SELECT
        CONCAT(origin_code, '-', dest_code) AS route,
        day_of_month,
        ROUND(AVG(dep_delay_minutes), 2) AS avg_delay_today
    FROM airline_dev.gold.fact_flights
    WHERE cancelled = 0
      AND dep_delay_minutes IS NOT NULL
      AND day_of_month IS NOT NULL
    GROUP BY origin_code, dest_code, day_of_month
)
SELECT
    route,
    day_of_month,
    avg_delay_today,
    LAG(avg_delay_today) OVER (PARTITION BY route ORDER BY day_of_month) AS avg_delay_yesterday,
    ROUND(
        avg_delay_today - LAG(avg_delay_today) OVER (PARTITION BY route ORDER BY day_of_month),
        2
    ) AS delay_change
FROM daily_delays
QUALIFY delay_change IS NOT NULL
ORDER BY delay_change DESC
LIMIT 15;

-- ============================================================
-- Query 9: Routes performing worse than network average
-- ============================================================
-- Business question: Which routes have average delays worse than
--   the overall network average? Show benchmark for context, 
--   minutes worse, and flight count for credibility.
-- Tables: airline_dev.gold.fact_flights
-- Concepts demonstrated:
--   - Empty OVER() for grand benchmark across groups
--   - HAVING for group-level filter (>= 30 flights)
--   - QUALIFY for window-result filter (worse than benchmark)
--   - Average-of-averages vs weighted-average distinction
-- Important nuance — avg-of-avg vs flight-weighted avg:
--   AVG(route_avg_delay) OVER () treats each route equally,
--   regardless of flight count. A 5-flight route counts as much
--   as a 200-flight route in the benchmark. This answers:
--     "Is this route worse than a typical route?"
--   For "what delay would a random flight experience?", you'd 
--   need AVG(dep_delay_minutes) over the raw fact table — that
--   weights by flight volume.
--   Different questions, different answers. Choose intentionally.
-- Findings:
--   - 3 routes worse than network average (14.23 min):
--       OGG-DFW (+23.86), LAX-JFK (+2.07), ORD-LGA (+0.99)
--   - OGG-DFW skewed by 1090-min outlier flight identified in Q8.
--     Median would be more robust to outliers — production
--     dashboards should report both.
--   - LAX-JFK appears in 3 queries: highest volume (Q2), highest
--     cancellation rate (Q4), worse-than-average delay (Q9).
--     Cross-query pattern flags this as a problem route.
-- ============================================================
WITH route_stats AS (
    SELECT
        CONCAT(origin_code, '-', dest_code) AS route,
        ROUND(AVG(dep_delay_minutes), 2) AS route_avg_delay,
        COUNT(*) AS total_flights
    FROM airline_dev.gold.fact_flights
    WHERE cancelled = 0
      AND dep_delay_minutes IS NOT NULL
    GROUP BY origin_code, dest_code
    HAVING COUNT(*) >= 30
)
SELECT
    route,
    route_avg_delay,
    ROUND(AVG(route_avg_delay) OVER (), 2) AS network_avg_delay,
    ROUND(route_avg_delay - AVG(route_avg_delay) OVER (), 2) AS minutes_worse_than_network,
    total_flights
FROM route_stats
QUALIFY route_avg_delay > AVG(route_avg_delay) OVER ()
ORDER BY minutes_worse_than_network DESC;

-- ============================================================
-- Query 10: Distance bucket cohort analysis
-- ============================================================
-- Business question: Group flights into haul-distance buckets
--   (Short/Medium/Long/Ultra-Long). For each cohort, compute
--   total flights, average delay, on-time rate, and cancel rate.
--   Does flight distance correlate with operational performance?
-- Tables: airline_dev.gold.fact_flights
-- Concepts demonstrated:
--   - CASE WHEN for continuous-to-categorical bucketing
--   - Parallel CASE for bucket_order (sort) + label (display)
--     -- avoids alphabetical ordering trap
--   - Conditional aggregation: multiple metrics with DIFFERENT
--     denominators in one pass
--       avg_delay: filter to non-cancelled INSIDE the AVG
--       on_time_rate: non-cancelled denominator
--       cancel_rate: full denominator (incl. cancelled)
--   - Mixing denominators is a classic interview trap. Each
--     metric answers a different question:
--       on-time = "of flights that flew, % on time?"
--       cancel  = "of flights attempted, % scrapped?"
-- BTS conventions: 
--   On-time = departure delay < 15 minutes
--   Distance brackets: <500, 500-1500, 1500-3000, 3000+
-- Findings:
--   - Long-haul: BEST on-time rate (85.16%) but WORST cancel
--     rate (5.98%). "Fly well or don't fly" — long-haul flights
--     are slot-protected when they go, cancelled when conditions
--     deteriorate (cascading delay across 5+ hours is operationally
--     catastrophic).
--   - Medium-haul (500-1500) is worst overall: highest delay 
--     (15 min), lowest on-time (78.81%). Hub-to-spoke flights
--     most exposed to upstream cascading delays.
--   - Ultra-long-haul: zero cancellations in 152 flights. Likely
--     protected international routes; small sample warrants caveat.
--   - Short-haul: reliable across all metrics. Quick turns, less
--     weather/ATC stacking exposure.
-- ============================================================
WITH bucketed AS (
    SELECT
        CASE
            WHEN distance_miles < 500 THEN 1
            WHEN distance_miles < 1500 THEN 2
            WHEN distance_miles < 3000 THEN 3
            ELSE 4
        END AS bucket_order,
        CASE
            WHEN distance_miles < 500 THEN 'Short-haul (<500 mi)'
            WHEN distance_miles < 1500 THEN 'Medium-haul (500-1500 mi)'
            WHEN distance_miles < 3000 THEN 'Long-haul (1500-3000 mi)'
            ELSE 'Ultra-long-haul (3000+ mi)'
        END AS distance_bucket,
        cancelled,
        dep_delay_minutes
    FROM airline_dev.gold.fact_flights
    WHERE distance_miles IS NOT NULL
)
SELECT
    distance_bucket,
    COUNT(*) AS total_flights,
    ROUND(AVG(CASE WHEN cancelled = 0 THEN dep_delay_minutes END), 2) AS avg_delay_minutes,
    ROUND(COUNT_IF(cancelled = 0 AND dep_delay_minutes < 15) * 100.0 / COUNT_IF(cancelled = 0), 2) AS on_time_rate_pct,
    ROUND(COUNT_IF(cancelled = 1) * 100.0 / COUNT(*), 2) AS cancellation_rate_pct
FROM bucketed
GROUP BY bucket_order, distance_bucket
ORDER BY bucket_order;
