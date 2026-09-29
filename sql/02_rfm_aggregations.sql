-- ============================================================
-- 02_RFM_AGGREGATIONS.SQL
-- Modular CTE Pipeline: Constructing the Analytical Base Table (ABT)
-- Grain: 1 Row = 1 customer_unique_id
-- ============================================================

WITH delivered_orders AS (
    -- Step 1: Filter strictly for completed, delivered orders with valid delivery dates
    SELECT 
        o.order_id,
        o.customer_id,
        c.customer_unique_id,
        c.customer_state,
        o.order_purchase_timestamp,
        o.order_delivered_customer_date,
        o.order_estimated_delivery_date,
        -- Delivery SLA delay metric in days (Positive = delayed, Negative = ahead of SLA)
        EXTRACT(EPOCH FROM (o.order_delivered_customer_date - o.order_estimated_delivery_date)) / 86400.0 AS delivery_delay_days
    FROM fact_orders o
    INNER JOIN dim_customers c ON o.customer_id = c.customer_id
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
),

order_items_preagg AS (
    -- Step 2: Pre-aggregate order items to prevent Cartesian duplication
    SELECT 
        order_id,
        SUM(price) AS total_item_price,
        SUM(freight_value) AS total_freight,
        COUNT(order_item_id) AS items_count
    FROM fact_order_items
    GROUP BY order_id
),

order_payments_preagg AS (
    -- Step 3: Pre-aggregate payments to identify dominant payment method and installments
    SELECT 
        order_id,
        SUM(payment_value) AS total_payment_value,
        AVG(payment_installments) AS avg_installments,
        -- Select dominant payment type using window ranking
        MAX(payment_type) AS primary_payment_type
    FROM fact_order_payments
    GROUP BY order_id
),

order_reviews_preagg AS (
    -- Step 4: Pre-aggregate customer reviews
    SELECT 
        order_id,
        AVG(review_score) AS order_review_score
    FROM fact_order_reviews
    GROUP BY order_id
),

order_level_enriched AS (
    -- Step 5: Join pre-aggregated dimension blocks
    SELECT 
        d.order_id,
        d.customer_unique_id,
        d.customer_state,
        d.order_purchase_timestamp,
        d.delivery_delay_days,
        COALESCE(i.total_item_price, 0) + COALESCE(i.total_freight, 0) AS total_order_spend,
        COALESCE(i.total_freight, 0) AS total_order_freight,
        COALESCE(i.items_count, 1) AS total_order_items,
        COALESCE(p.avg_installments, 1) AS avg_installments,
        COALESCE(p.primary_payment_type, 'credit_card') AS primary_payment_type,
        COALESCE(r.order_review_score, 4.0) AS order_review_score
    FROM delivered_orders d
    LEFT JOIN order_items_preagg i ON d.order_id = i.order_id
    LEFT JOIN order_payments_preagg p ON d.order_id = p.order_id
    LEFT JOIN order_reviews_preagg r ON d.order_id = r.order_id
),

anchor_reference AS (
    -- Step 6: Dynamic global anchor date (Max purchase timestamp + 1 day)
    SELECT MAX(order_purchase_timestamp) + INTERVAL '1 day' AS anchor_date
    FROM order_level_enriched
)

-- Step 7: Final Customer Analytical Base Table (ABT)
SELECT 
    o.customer_unique_id,
    
    -- Recency: Days between global anchor date and customer's latest purchase
    ROUND(EXTRACT(EPOCH FROM (a.anchor_date - MAX(o.order_purchase_timestamp))) / 86400.0, 1) AS recency_days,
    
    -- Frequency: Total delivered orders
    COUNT(DISTINCT o.order_id) AS frequency,
    
    -- Monetary: Total gross spend (Products + Freight)
    ROUND(SUM(o.total_order_spend), 2) AS monetary_value,
    
    -- Average Order Value
    ROUND(SUM(o.total_order_spend) / COUNT(DISTINCT o.order_id), 2) AS avg_order_value,
    
    -- Shipping Friction: Freight-to-spend ratio
    ROUND(SUM(o.total_order_freight) / (SUM(o.total_order_spend) + 0.0001), 4) AS freight_ratio,
    
    -- Customer Satisfaction & Operational Lag
    ROUND(AVG(o.order_review_score), 2) AS avg_review_score,
    ROUND(AVG(o.delivery_delay_days), 2) AS avg_delivery_delay_days,
    ROUND(MAX(o.delivery_delay_days), 2) AS max_delivery_delay_days,
    
    -- Payment Behavior
    ROUND(AVG(o.avg_installments), 1) AS avg_payment_installments,
    
    -- Geographic & Behavioral Profile
    MAX(o.customer_state) AS customer_state,
    MAX(o.primary_payment_type) AS preferred_payment_type

FROM order_level_enriched o
CROSS JOIN anchor_reference a
GROUP BY o.customer_unique_id, a.anchor_date;
