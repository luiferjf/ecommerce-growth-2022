/*
===============================================================================
SCRIPT NAME:    04_data_exports.sql
DESCRIPTION:    Extraction queries used to generate the static CSV datasets
                for the Tableau Public dashboard.
                
                These scripts document the exact logic behind each CSV file
                in the /data directory, enabling full reproducibility.
                
                Run against: u298795178_foundation_v1 (MariaDB, Hostinger)
AUTHOR:         Luis Fernando Jordan
DATE:           2022-01-24
===============================================================================
*/


-- =============================================================================
-- EXPORT 1: kpi_daily_store.csv
-- PURPOSE:  Primary dataset for Tableau. Daily-level KPIs per store.
--           Covers FY 2021 (for YoY comparison) and FY 2022 (the focus year).
--           Only includes days with actual transaction activity (orders > 0).
-- =============================================================================

SELECT
    date_key,
    date,
    year,
    month,
    month_name,
    iso_year,
    iso_week,
    iso_yearweek,
    week_start_date,
    store_code,
    store_name,
    orders,
    net_revenue,
    aov,
    units,
    asp,
    units_per_order
FROM vw_kpi_daily_store
WHERE year IN (2021, 2022)
  AND orders > 0
ORDER BY date, store_code;


-- =============================================================================
-- EXPORT 2: kpi_store_summary.csv
-- PURPOSE:  All-time aggregate summary per store (used for KPI scorecard).
-- =============================================================================

SELECT
    store_code,
    store_name,
    orders,
    net_revenue,
    aov,
    units,
    asp,
    units_per_order
FROM vw_kpi_store_summary
ORDER BY store_code;


-- =============================================================================
-- EXPORT 3: revenue_by_year_store.csv
-- PURPOSE:  Annual revenue per store for 2020-2022.
--           Supports the portfolio diversification historical context analysis.
-- =============================================================================

SELECT
    s.store_code,
    s.store_name,
    d.year,
    COUNT(*)                                        AS orders,
    SUM(fo.net_revenue)                             AS net_revenue,
    ROUND(SUM(fo.net_revenue) / COUNT(*), 2)        AS aov
FROM fact_orders fo
JOIN dim_date  d ON d.date_key  = fo.date_key
JOIN dim_store s ON s.store_key = fo.store_key
WHERE d.year IN (2020, 2021, 2022)
GROUP BY s.store_code, s.store_name, d.year
ORDER BY d.year, s.store_code;


-- =============================================================================
-- EXPORT 4: revenue_bridge.csv
-- PURPOSE:  Pre-calculated waterfall data for the Revenue Bridge chart.
--           Decomposes 2021→2022 revenue variance into Volume and Price impact.
--
-- METHODOLOGY (Price-Volume Decomposition):
--   Volume Impact = (CY_Orders − PY_Orders) × PY_AOV
--   Price Impact  = (CY_AOV    − PY_AOV)    × CY_Orders
--
--   This is a standard financial bridge decomposition.
--   The "base" column represents the starting Y-axis position for
--   each floating Gantt bar in the Tableau waterfall visualization.
-- =============================================================================

-- Step 1: Calculate the anchor metrics for both years
WITH
annual_kpi AS (
    SELECT
        d.year,
        COUNT(*)                                    AS orders,
        SUM(fo.net_revenue)                         AS net_revenue,
        ROUND(SUM(fo.net_revenue) / COUNT(*), 2)    AS aov
    FROM fact_orders fo
    JOIN dim_date d ON d.date_key = fo.date_key
    WHERE d.year IN (2021, 2022)
    GROUP BY d.year
),
py AS (SELECT * FROM annual_kpi WHERE year = 2021),
cy AS (SELECT * FROM annual_kpi WHERE year = 2022),

-- Step 2: Compute the bridge components
bridge_calc AS (
    SELECT
        py.net_revenue                                              AS py_revenue,
        cy.net_revenue                                              AS cy_revenue,
        ROUND((cy.orders - py.orders) * py.aov, 2)                 AS volume_impact,
        ROUND((cy.aov - py.aov) * cy.orders, 2)                    AS price_impact
    FROM py, cy
)

-- Step 3: Build the waterfall rows with base positions
SELECT 1 AS step, 'FY 2021 — Baseline' AS label, 'Total Revenue'  AS category,
       0           AS base, py_revenue    AS value FROM bridge_calc
UNION ALL
SELECT 2, 'Volume Growth',      'Growth Driver', py_revenue,                        volume_impact FROM bridge_calc
UNION ALL
SELECT 3, 'Price Improvement',  'Growth Driver', py_revenue + volume_impact,        price_impact  FROM bridge_calc
UNION ALL
SELECT 4, 'FY 2022 — Result',   'Total Revenue', 0,                                 cy_revenue    FROM bridge_calc
ORDER BY step;
