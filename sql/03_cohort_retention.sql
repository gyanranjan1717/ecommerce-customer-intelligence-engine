-- ============================================================
-- 03_COHORT_RETENTION.SQL
-- Month-over-Month Customer Retention Decay Matrix
-- Evaluates repurchase behavior across 12 monthly cohorts
-- ============================================================

WITH customer_first_purchase AS (
    -- Identify the acquisition month (Cohort Month) for each unique customer
    SELECT 
        c.customer_unique_id,
        DATE_TRUNC('month', MIN(o.order_purchase_timestamp)) AS cohort_month
    FROM fact_orders o
    INNER JOIN dim_customers c ON o.customer_id = c.customer_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
),

customer_orders_timeline AS (
    -- Map each subsequent purchase month
    SELECT 
        c.customer_unique_id,
        DATE_TRUNC('month', o.order_purchase_timestamp) AS order_month
    FROM fact_orders o
    INNER JOIN dim_customers c ON o.customer_id = c.customer_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id, DATE_TRUNC('month', o.order_purchase_timestamp)
),

cohort_activity AS (
    -- Calculate month index (Month 0, Month 1, Month 2...)
    SELECT 
        f.cohort_month,
        (EXTRACT(YEAR FROM t.order_month) - EXTRACT(YEAR FROM f.cohort_month)) * 12 +
        (EXTRACT(MONTH FROM t.order_month) - EXTRACT(MONTH FROM f.cohort_month)) AS period_month,
        COUNT(DISTINCT f.customer_unique_id) AS active_customers
    FROM customer_first_purchase f
    JOIN customer_orders_timeline t ON f.customer_unique_id = t.customer_unique_id
    GROUP BY f.cohort_month, period_month
),

cohort_sizes AS (
    -- Baseline cohort size at Month 0
    SELECT 
        cohort_month,
        active_customers AS cohort_size
    FROM cohort_activity
    WHERE period_month = 0
)

-- Final Retention Matrix Query
SELECT 
    TO_CHAR(a.cohort_month, 'YYYY-MM') AS cohort,
    s.cohort_size,
    a.period_month,
    a.active_customers,
    ROUND((a.active_customers::NUMERIC / s.cohort_size) * 100.0, 2) AS retention_rate_pct
FROM cohort_activity a
JOIN cohort_sizes s ON a.cohort_month = s.cohort_month
WHERE a.cohort_month >= '2017-01-01' -- Focus on fully established calendar year
ORDER BY a.cohort_month, a.period_month;
