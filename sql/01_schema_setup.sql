-- ============================================================
-- 01_SCHEMA_SETUP.SQL
-- DDL Definitions with Primary & Foreign Key Constraints
-- Target Database: PostgreSQL / DuckDB
-- ============================================================

-- 1. Customers Dimension Table
CREATE TABLE IF NOT EXISTS dim_customers (
    customer_id VARCHAR(50) PRIMARY KEY,
    customer_unique_id VARCHAR(50) NOT NULL,
    customer_zip_code_prefix INT,
    customer_city VARCHAR(100),
    customer_state VARCHAR(5)
);

CREATE INDEX IF NOT EXISTS idx_customers_unique_id ON dim_customers(customer_unique_id);

-- 2. Orders Fact Table
CREATE TABLE IF NOT EXISTS fact_orders (
    order_id VARCHAR(50) PRIMARY KEY,
    customer_id VARCHAR(50) NOT NULL,
    order_status VARCHAR(20) NOT NULL,
    order_purchase_timestamp TIMESTAMP NOT NULL,
    order_approved_at TIMESTAMP,
    order_delivered_carrier_date TIMESTAMP,
    order_delivered_customer_date TIMESTAMP,
    order_estimated_delivery_date TIMESTAMP NOT NULL,
    CONSTRAINT fk_orders_customer FOREIGN KEY (customer_id) REFERENCES dim_customers(customer_id)
);

CREATE INDEX IF NOT EXISTS idx_orders_status ON fact_orders(order_status);
CREATE INDEX IF NOT EXISTS idx_orders_purchase_time ON fact_orders(order_purchase_timestamp);

-- 3. Order Items Fact Table (1-to-Many with Orders)
CREATE TABLE IF NOT EXISTS fact_order_items (
    order_id VARCHAR(50) NOT NULL,
    order_item_id INT NOT NULL,
    product_id VARCHAR(50) NOT NULL,
    seller_id VARCHAR(50) NOT NULL,
    shipping_limit_date TIMESTAMP,
    price NUMERIC(10, 2) NOT NULL,
    freight_value NUMERIC(10, 2) NOT NULL,
    PRIMARY KEY (order_id, order_item_id),
    CONSTRAINT fk_items_order FOREIGN KEY (order_id) REFERENCES fact_orders(order_id)
);

-- 4. Order Payments Fact Table (1-to-Many with Orders)
CREATE TABLE IF NOT EXISTS fact_order_payments (
    order_id VARCHAR(50) NOT NULL,
    payment_sequential INT NOT NULL,
    payment_type VARCHAR(30) NOT NULL,
    payment_installments INT NOT NULL,
    payment_value NUMERIC(10, 2) NOT NULL,
    PRIMARY KEY (order_id, payment_sequential),
    CONSTRAINT fk_payments_order FOREIGN KEY (order_id) REFERENCES fact_orders(order_id)
);

-- 5. Order Reviews Fact Table
CREATE TABLE IF NOT EXISTS fact_order_reviews (
    review_id VARCHAR(50) NOT NULL,
    order_id VARCHAR(50) NOT NULL,
    review_score INT CHECK (review_score BETWEEN 1 AND 5),
    review_comment_title TEXT,
    review_comment_message TEXT,
    review_creation_date TIMESTAMP,
    review_answer_timestamp TIMESTAMP,
    PRIMARY KEY (review_id, order_id),
    CONSTRAINT fk_reviews_order FOREIGN KEY (order_id) REFERENCES fact_orders(order_id)
);
