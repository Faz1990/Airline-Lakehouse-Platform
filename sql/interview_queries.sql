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