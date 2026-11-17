-- Creating the database:
-- We should run this command separately. then connect to 'ecommerce_marketplace'
CREATE DATABASE ecommerce_marketplace;
-- Connect to the created DB

-- Creating the schema for a reusable and rerunnable code
CREATE SCHEMA IF NOT EXISTS marketplace;
SET search_path TO marketplace;

--PARENT TABLES FIRST
/*Why correct DDL order matters:
 *- Parent tables must be created before child tables because the referencing tables need 
 *referenced ones to establish the relationship between them
 *- The FOREIGN KEYs require a valid target table and a column with a PRIMARY KEY constraint that already exists in the DB
 *- PostgreSQL returns an error if the order expectations are not met: ERROR: relation "<parent_table_name>" does not exist (SQLSTATE 42P01).*/

/*Why INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY is used:
 * Uses the ANSI SQL standard for new versions of PostgreSQL, preventing accidental manual
 * overrides of surrogate primary keys and keeping sequence permissions tied to the table.*/

/*WHAT ARE THE RISKS OF CHOOSING WRONG DATA TYPE:
 * - Choosing a larger type than needed (BIGINT instead of INT) wastes memory/disk
 *space and increases index size.
 *- Choosing a smaller type than needed (SMALLINT) risks numeric overflow errors
 *as data grows.
 *- Assigning a character type (VARCHAR/TEXT) to numeric or date values prevents
 *mathematical calculations, aggregations, proper sorting, and causes runtime errors.
 *- Using FLOAT instead of NUMERIC for money causes binary rounding inaccuracies.*/

/*WHAT HAPPENS IF FK IS MISSING
 *- Referential integrity is not enforced at the database level; the tables would act
 *as isolated tables with no relational validation between them.
 *- This allows "orphan records" (an order referencing a non-existent buyer_id)
 *and permits deleting a parent record while child records still depend on it. */


CREATE TABLE IF NOT EXISTS marketplace.sellers(
	seller_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	-- VARCHAR(50) enforces a length limit for names (in PostgreSQL, VARCHAR and TEXT
    -- use the same storage mechanism, VARCHAR(n) is used strictly for length validation).
	name VARCHAR(50) NOT NULL,
	surname VARCHAR(50) NOT NULL,
	-- VARCHAR(200) provides sufficient length for company names while preventing oversized input.
	company_name VARCHAR(200),
	-- TEXT is used for addresses because their length is unpredictable and has no fixed upper bound.
	address TEXT,
	-- VARCHAR(20) accommodates international phone formats (+359...).
    -- NOT NULL + UNIQUE prevents missing phone numbers and duplicate seller accounts with the same number;
    -- without UNIQUE, multiple accounts could share one phone number.
	phone_num VARCHAR(20) NOT NULL UNIQUE 
);

CREATE TABLE IF NOT EXISTS marketplace.buyers(
	buyer_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	name VARCHAR(50) NOT NULL,
	surname VARCHAR(50) NOT NULL,
	address TEXT,
	-- NOT NULL + UNIQUE ensures every buyer has a unique phone number; without it, 
	-- duplicate customer profiles would split order history and distort customer analytics.
	phone_num VARCHAR(20) NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS marketplace.product_category(
	category_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	-- Prevents duplicate category names and empty labels. Without UNIQUE, products and category
    -- promotions would split across duplicate categories.
	category_name VARCHAR(100) NOT NULL UNIQUE 
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_product_category_name_upper
    ON marketplace.product_category (UPPER(category_name));

CREATE TABLE IF NOT EXISTS marketplace.products(
	product_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	seller_id INT NOT NULL REFERENCES marketplace.sellers(seller_id),
	category_id INT NOT NULL REFERENCES marketplace.product_category(category_id),
	-- Added product_name (adjusted from initial logical model) as a unique catalog
    -- prevents duplicate product listings and allows identifying items without parsing descriptions.
	product_name VARCHAR(200) NOT NULL UNIQUE, 
	description TEXT,
	-- NUMERIC(10, 2) guarantees exact decimal arithmetic for currency.
    -- The check constraint Prevents negative prices; without it, negative prices would corrupt order totals and refunds.
	price NUMERIC(10,2) NOT NULL CHECK (price >= 0) 
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_products_name_upper
    ON marketplace.products (UPPER(product_name));

CREATE TABLE IF NOT EXISTS marketplace.inventory(
	stock_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	product_id INT NOT NULL REFERENCES marketplace.products(product_id),
	quantity_change INT NOT NULL,
	-- DEFAULT assigns current timestamp when omitted.
    -- Prevents invalid historical/corrupted dates (1970-01-01); without it, stock history
    -- and time-series inventory audits would be inaccurate.
	transaction_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP CHECK (transaction_date > '2000-01-01 00:00:00')
);
CREATE TABLE IF NOT EXISTS marketplace.orders(
	order_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	buyer_id INT NOT NULL REFERENCES marketplace.buyers(buyer_id),
	-- DEFAULT assigns current timestamp if no date is provided.
    -- Date > January 1, 2000: Prevents invalid pre-2000 order dates.
	order_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP CHECK (order_date > '2000-01-01 00:00:00')
);
CREATE TABLE IF NOT EXISTS marketplace.order_items(
	order_id INT REFERENCES marketplace.orders(order_id) NOT NULL,
	product_id INT REFERENCES marketplace.products(product_id) NOT NULL,
	-- CHECK prevents zero or negative quantities, without it, orders could contain 0 or negative items
    -- and distort revenue and stock calculations.
	quantity INT NOT NULL CHECK(quantity > 0), 
	-- Preserves the historical price at the moment of purchase (3NF).
	-- excludes negative numbers as prices
	price_at_purchase NUMERIC(10, 2) NOT NULL CHECK(price_at_purchase >= 0), 
	-- GENERATED ALWAYS AS column (added to physical model to ensure consistent line subtotals
    -- and prevent update anomalies between quantity, price_at_purchase, and line_total).
    line_total NUMERIC(12, 2) GENERATED ALWAYS AS (quantity * price_at_purchase) STORED,
	PRIMARY KEY(order_id, product_id)
);
CREATE TABLE IF NOT EXISTS marketplace.payments(
	payment_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	order_id INT NOT NULL REFERENCES marketplace.orders(order_id),
	-- CONSTRAINT(Non-negative value): Prevents negative payment amounts.
	amount NUMERIC(10, 2) NOT NULL CHECK(amount >= 0), 
	-- CONSTRAINT(Date > January 1, 2000):
    -- Ensures no pre-2000 payments are recorded; without it, corrupted system dates would break financial reports.
	-- DEFAULT value is the current date and time of the payment
	date_and_time TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP CHECK (date_and_time > '2000-01-01 00:00:00'), 
    -- Restricts status to four valid states; without it, typos or invalid strings (e.g., 'paid')
    -- would break payment tracking and status filtering.
	status VARCHAR(50) NOT NULL CHECK (UPPER(status) IN ('PENDING', 'COMPLETED', 'FAILED', 'REFUNDED')) 
);
CREATE TABLE IF NOT EXISTS marketplace.deliveries(
	delivery_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	order_id INT NOT NULL REFERENCES marketplace.orders(order_id),
	-- Restricts delivery status to four valid states; without it, inconsistent status labels
    -- would disrupt order fulfillment workflows.
	status VARCHAR(50) NOT NULL CHECK (UPPER(status) IN ('PROCESSING', 'SHIPPED', 'DELIVERED', 'CANCELED')), 
	-- DEFAULT assigns current timestamp if no date is provided.
	date_changed TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP CHECK (date_changed > '2000-01-01 00:00:00')
);

CREATE TABLE IF NOT EXISTS marketplace.reviews(
	review_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	buyer_id INT NOT NULL REFERENCES marketplace.buyers(buyer_id),
	product_id INT NOT NULL REFERENCES marketplace.products(product_id),
	-- INT is required to calculate average product ratings, CHECK restricts values to 1-5 stars.
    -- Without this CHECK, out-of-range ratings would skew average product scores.
	rating INT NOT NULL CHECK(rating >= 1 AND rating <= 5), 
	-- TEXT is used because review length is unpredictable free-form text.
	review_text TEXT,
	-- if no date provided, current date is assigned to the field
	review_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP CHECK (review_date > '2000-01-01 00:00:00'),
	-- The composite unique ensures one buyer can submit only one review per product; without it, a user could spam
    -- multiple reviews and artificially manipulate a product's rating.
	UNIQUE(buyer_id, product_id) 
);
CREATE TABLE IF NOT EXISTS marketplace.discounts (
	discount_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	product_id INT NOT NULL REFERENCES marketplace.products(product_id),
	-- Prevents zero or negative discounts, without it, a negative discount would mistakenly increase the price.
	discount_amount NUMERIC(10, 2) NOT NULL CHECK(discount_amount > 0),
	start_date TIMESTAMP NOT NULL CHECK (start_date > '2000-01-01 00:00:00'),
	end_date TIMESTAMP NOT NULL,
	-- Ensures logical date interval, without it, a discount could end before it starts.
	CHECK(end_date > start_date) 
);
CREATE TABLE IF NOT EXISTS marketplace.promotions (
	promotion_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	category_id INT NOT NULL REFERENCES marketplace.product_category(category_id),
	-- Restricts percentage to valid range (0, 100]; without it, discounts over 100% would result in negative prices.
	promotion_percent NUMERIC(5, 2) NOT NULL CHECK(promotion_percent > 0 AND promotion_percent <= 100), 
	start_date TIMESTAMP NOT NULL CHECK (start_date > '2000-01-01 00:00:00'),
	end_date TIMESTAMP NOT NULL, 
	-- Ensures logical date interval between start_date and end_date.
	CHECK(end_date > start_date) 
);
/* HOW DATA CONSISTENCY AND RELATIONSHIPS ARE PRESERVED:
 * - Rows are inserted strictly in parent-to-child order matching table dependencies.
 * - Surrogate primary keys (IDENTITY columns) are never hardcoded; child tables
 *   resolve foreign keys dynamically via subqueries/joins on natural keys
 *   (phone_num, category_name, product_name, order_date).
 * - ON CONFLICT DO NOTHING and WHERE NOT EXISTS make the script rerunnable
 *   without creating duplicate rows or violating unique constraints. */


INSERT INTO marketplace.sellers (name, surname, company_name, address, phone_num)
VALUES
    ('Nikolay', 'Mravov', 'Solaria EOOD', 'Sliven, Industrial Zone, ul. Samuilovsko Shose 12', '+359887412589'),
    ('Radinela', 'Mravova', 'Aura Beauty Lab', 'Sofia, kv. Lozenets, ul. Zlatovrah 34', '+359889632147')
ON CONFLICT (phone_num) DO NOTHING;


INSERT INTO marketplace.buyers (name, surname, address, phone_num)
VALUES
    ('Yuliyana', 'Mravova', 'Sofia, Studentski Grad, bl. 59', '+359895147258'),
    ('Zlatina', 'Vasileva', 'Stara Zagora, bul. Tsar Simeon Veliki 104', '+359896369852')
ON CONFLICT (phone_num) DO NOTHING;


INSERT INTO marketplace.product_category (category_name)
VALUES
    ('Cleaning & Disinfectants'),
    ('Skincare & Cosmetics')
ON CONFLICT (category_name) DO NOTHING;


INSERT INTO marketplace.products (seller_id, category_id, product_name, description, price)
SELECT
    s.seller_id,
    c.category_id,
    'Solaria Multi-Surface Disinfectant 5L',
    'Professional bactericidal surface cleaner and disinfectant for home and industrial use',
    24.80
FROM marketplace.sellers s
CROSS JOIN marketplace.product_category c
WHERE s.phone_num = '+359887412589'
  AND UPPER(c.category_name) = UPPER('Cleaning & Disinfectants')
ON CONFLICT (product_name) DO NOTHING;

INSERT INTO marketplace.products (seller_id, category_id, product_name, description, price)
SELECT
    s.seller_id,
    c.category_id,
    'Azelaic Acid & Niacinamide Balancing Serum 30ml',
    'Daily soothing serum for combination skin with 10% azelaic acid and vitamin B3',
    32.50
FROM marketplace.sellers s
CROSS JOIN marketplace.product_category c
WHERE s.phone_num = '+359889632147'
  AND UPPER(c.category_name) = UPPER('Skincare & Cosmetics')
ON CONFLICT (product_name) DO NOTHING;


INSERT INTO marketplace.inventory (product_id, quantity_change, transaction_date)
SELECT
    p.product_id,
    120,
    TIMESTAMP '2026-10-05 09:30:00'
FROM marketplace.products p
WHERE UPPER(p.product_name) = UPPER('Solaria Multi-Surface Disinfectant 5L')
  AND NOT EXISTS (
      SELECT 1 FROM marketplace.inventory i
      WHERE i.product_id = p.product_id AND i.transaction_date = TIMESTAMP '2026-10-05 09:30:00'
  );

INSERT INTO marketplace.inventory (product_id, quantity_change, transaction_date)
SELECT
    p.product_id,
    45,
    TIMESTAMP '2026-10-06 11:15:00'
FROM marketplace.products p
WHERE UPPER(p.product_name) = UPPER('Azelaic Acid & Niacinamide Balancing Serum 30ml')
  AND NOT EXISTS (
      SELECT 1 FROM marketplace.inventory i
      WHERE i.product_id = p.product_id AND i.transaction_date = TIMESTAMP '2026-10-06 11:15:00'
  );


INSERT INTO marketplace.orders (buyer_id, order_date)
SELECT
    b.buyer_id,
    TIMESTAMP '2026-10-20 13:40:00'
FROM marketplace.buyers b
WHERE b.phone_num = '+359895147258'
  AND NOT EXISTS (
      SELECT 1 FROM marketplace.orders o
      WHERE o.buyer_id = b.buyer_id AND o.order_date = TIMESTAMP '2026-10-20 13:40:00'
  );

INSERT INTO marketplace.orders (buyer_id, order_date)
SELECT
    b.buyer_id,
    TIMESTAMP '2026-10-22 17:10:00'
FROM marketplace.buyers b
WHERE b.phone_num = '+359896369852'
  AND NOT EXISTS (
      SELECT 1 FROM marketplace.orders o
      WHERE o.buyer_id = b.buyer_id AND o.order_date = TIMESTAMP '2026-10-22 17:10:00'
  );


INSERT INTO marketplace.order_items (order_id, product_id, quantity, price_at_purchase)
SELECT
    o.order_id,
    p.product_id,
    2,
    p.price
FROM marketplace.orders o
CROSS JOIN marketplace.products p
WHERE o.order_date = TIMESTAMP '2026-10-20 13:40:00'
  AND UPPER(p.product_name) = UPPER('Solaria Multi-Surface Disinfectant 5L')
ON CONFLICT (order_id, product_id) DO NOTHING;

INSERT INTO marketplace.order_items (order_id, product_id, quantity, price_at_purchase)
SELECT
    o.order_id,
    p.product_id,
    1,
    p.price
FROM marketplace.orders o
CROSS JOIN marketplace.products p
WHERE o.order_date = TIMESTAMP '2026-10-22 17:10:00'
  AND UPPER(p.product_name) = UPPER('Azelaic Acid & Niacinamide Balancing Serum 30ml')
ON CONFLICT (order_id, product_id) DO NOTHING;


INSERT INTO marketplace.payments (order_id, amount, date_and_time, status)
SELECT
    o.order_id,
    COALESCE((SELECT SUM(oi.line_total) FROM marketplace.order_items oi WHERE oi.order_id = o.order_id), 0),
    TIMESTAMP '2026-10-20 13:42:00',
    'Completed'
FROM marketplace.orders o
WHERE o.order_date = TIMESTAMP '2026-10-20 13:40:00'
  AND NOT EXISTS (
      SELECT 1 FROM marketplace.payments pay WHERE pay.order_id = o.order_id
  );

INSERT INTO marketplace.payments (order_id, amount, date_and_time, status)
SELECT
    o.order_id,
    COALESCE((SELECT SUM(oi.line_total) FROM marketplace.order_items oi WHERE oi.order_id = o.order_id), 0),
    TIMESTAMP '2026-10-22 17:15:00',
    'Pending'
FROM marketplace.orders o
WHERE o.order_date = TIMESTAMP '2026-10-22 17:10:00'
  AND NOT EXISTS (
      SELECT 1 FROM marketplace.payments pay WHERE pay.order_id = o.order_id
  );


INSERT INTO marketplace.deliveries (order_id, status, date_changed)
SELECT
    o.order_id,
    'Delivered',
    TIMESTAMP '2026-10-23 10:20:00'
FROM marketplace.orders o
WHERE o.order_date = TIMESTAMP '2026-10-20 13:40:00'
  AND NOT EXISTS (
      SELECT 1 FROM marketplace.deliveries d WHERE d.order_id = o.order_id
  );

INSERT INTO marketplace.deliveries (order_id, status, date_changed)
SELECT
    o.order_id,
    'Shipped',
    TIMESTAMP '2026-10-24 15:05:00'
FROM marketplace.orders o
WHERE o.order_date = TIMESTAMP '2026-10-22 17:10:00'
  AND NOT EXISTS (
      SELECT 1 FROM marketplace.deliveries d WHERE d.order_id = o.order_id
  );


INSERT INTO marketplace.reviews (buyer_id, product_id, rating, review_text, review_date)
SELECT
    b.buyer_id,
    p.product_id,
    5,
    'Very effective cleaner with a fresh scent, great value for a 5L canister.',
    TIMESTAMP '2026-10-25 19:30:00'
FROM marketplace.buyers b
CROSS JOIN marketplace.products p
WHERE b.phone_num = '+359895147258'
  AND UPPER(p.product_name) = UPPER('Solaria Multi-Surface Disinfectant 5L')
ON CONFLICT (buyer_id, product_id) DO NOTHING;

INSERT INTO marketplace.reviews (buyer_id, product_id, rating, review_text, review_date)
SELECT
    b.buyer_id,
    p.product_id,
    5,
    'Lightweight texture, absorbs quickly and calms redness within a few days.',
    TIMESTAMP '2026-10-26 14:15:00'
FROM marketplace.buyers b
CROSS JOIN marketplace.products p
WHERE b.phone_num = '+359896369852'
  AND UPPER(p.product_name) = UPPER('Azelaic Acid & Niacinamide Balancing Serum 30ml')
ON CONFLICT (buyer_id, product_id) DO NOTHING;


INSERT INTO marketplace.discounts (product_id, discount_amount, start_date, end_date)
SELECT
    p.product_id,
    4.80,
    TIMESTAMP '2026-11-01 00:00:00',
    TIMESTAMP '2026-11-30 23:59:59'
FROM marketplace.products p
WHERE UPPER(p.product_name) = UPPER('Solaria Multi-Surface Disinfectant 5L')
  AND NOT EXISTS (
      SELECT 1 FROM marketplace.discounts d
      WHERE d.product_id = p.product_id AND d.start_date = '2026-11-01 00:00:00'
  );

INSERT INTO marketplace.discounts (product_id, discount_amount, start_date, end_date)
SELECT
    p.product_id,
    5.00,
    TIMESTAMP '2026-11-10 00:00:00',
    TIMESTAMP '2026-11-25 23:59:59'
FROM marketplace.products p
WHERE UPPER(p.product_name) = UPPER('Azelaic Acid & Niacinamide Balancing Serum 30ml')
  AND NOT EXISTS (
      SELECT 1 FROM marketplace.discounts d
      WHERE d.product_id = p.product_id AND d.start_date = TIMESTAMP '2026-11-10 00:00:00'
  );


INSERT INTO marketplace.promotions (category_id, promotion_percent, start_date, end_date)
SELECT
    c.category_id,
    15.00,
    TIMESTAMP '2026-11-15 00:00:00',
    TIMESTAMP '2026-11-30 23:59:59'
FROM marketplace.product_category c
WHERE UPPER(c.category_name) = UPPER('Cleaning & Disinfectants')
  AND NOT EXISTS (
      SELECT 1 FROM marketplace.promotions pr
      WHERE pr.category_id = c.category_id AND pr.start_date = TIMESTAMP '2026-11-15 00:00:00'
  );

INSERT INTO marketplace.promotions (category_id, promotion_percent, start_date, end_date)
SELECT
    c.category_id,
    20.00,
    TIMESTAMP '2026-11-20 00:00:00',
    TIMESTAMP '2026-12-05 23:59:59'
FROM marketplace.product_category c
WHERE UPPER(c.category_name) = UPPER('Skincare & Cosmetics')
  AND NOT EXISTS (
      SELECT 1 FROM marketplace.promotions pr
      WHERE pr.category_id = c.category_id AND pr.start_date = '2026-11-20 00:00:00'
  );


ALTER TABLE marketplace.sellers          ADD COLUMN IF NOT EXISTS record_ts DATE NOT NULL DEFAULT CURRENT_DATE;
ALTER TABLE marketplace.buyers           ADD COLUMN IF NOT EXISTS record_ts DATE NOT NULL DEFAULT CURRENT_DATE;
ALTER TABLE marketplace.product_category ADD COLUMN IF NOT EXISTS record_ts DATE NOT NULL DEFAULT CURRENT_DATE;
ALTER TABLE marketplace.products         ADD COLUMN IF NOT EXISTS record_ts DATE NOT NULL DEFAULT CURRENT_DATE;
ALTER TABLE marketplace.inventory        ADD COLUMN IF NOT EXISTS record_ts DATE NOT NULL DEFAULT CURRENT_DATE;
ALTER TABLE marketplace.orders           ADD COLUMN IF NOT EXISTS record_ts DATE NOT NULL DEFAULT CURRENT_DATE;
ALTER TABLE marketplace.order_items      ADD COLUMN IF NOT EXISTS record_ts DATE NOT NULL DEFAULT CURRENT_DATE;
ALTER TABLE marketplace.payments         ADD COLUMN IF NOT EXISTS record_ts DATE NOT NULL DEFAULT CURRENT_DATE;
ALTER TABLE marketplace.deliveries       ADD COLUMN IF NOT EXISTS record_ts DATE NOT NULL DEFAULT CURRENT_DATE;
ALTER TABLE marketplace.reviews          ADD COLUMN IF NOT EXISTS record_ts DATE NOT NULL DEFAULT CURRENT_DATE;
ALTER TABLE marketplace.discounts        ADD COLUMN IF NOT EXISTS record_ts DATE NOT NULL DEFAULT CURRENT_DATE;
ALTER TABLE marketplace.promotions       ADD COLUMN IF NOT EXISTS record_ts DATE NOT NULL DEFAULT CURRENT_DATE;

SELECT 'sellers' AS table_name, COUNT(*) AS rows_count, COUNT(record_ts) AS record_ts_filled, MIN(record_ts) AS sample_date FROM marketplace.sellers
UNION ALL SELECT 'buyers',           COUNT(*), COUNT(record_ts), MIN(record_ts) FROM marketplace.buyers
UNION ALL SELECT 'product_category', COUNT(*), COUNT(record_ts), MIN(record_ts) FROM marketplace.product_category
UNION ALL SELECT 'products',         COUNT(*), COUNT(record_ts), MIN(record_ts) FROM marketplace.products
UNION ALL SELECT 'inventory',        COUNT(*), COUNT(record_ts), MIN(record_ts) FROM marketplace.inventory
UNION ALL SELECT 'orders',           COUNT(*), COUNT(record_ts), MIN(record_ts) FROM marketplace.orders
UNION ALL SELECT 'order_items',      COUNT(*), COUNT(record_ts), MIN(record_ts) FROM marketplace.order_items
UNION ALL SELECT 'payments',         COUNT(*), COUNT(record_ts), MIN(record_ts) FROM marketplace.payments
UNION ALL SELECT 'deliveries',       COUNT(*), COUNT(record_ts), MIN(record_ts) FROM marketplace.deliveries
UNION ALL SELECT 'reviews',          COUNT(*), COUNT(record_ts), MIN(record_ts) FROM marketplace.reviews
UNION ALL SELECT 'discounts',        COUNT(*), COUNT(record_ts), MIN(record_ts) FROM marketplace.discounts
UNION ALL SELECT 'promotions',       COUNT(*), COUNT(record_ts), MIN(record_ts) FROM marketplace.promotions
ORDER BY table_name;



