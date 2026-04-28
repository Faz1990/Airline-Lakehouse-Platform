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