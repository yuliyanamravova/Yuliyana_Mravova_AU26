-- Creating the database:
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
 * - Choosing a larger type than needed (e.g., BIGINT instead of INT) wastes memory/disk
 *space and increases index size.
 *- Choosing a smaller type than needed (e.g., SMALLINT) risks numeric overflow errors
 *as data grows.
 *- Assigning a character type (VARCHAR/TEXT) to numeric or date values prevents
 *mathematical calculations, aggregations, proper sorting, and causes runtime errors.
 *- Using FLOAT instead of NUMERIC for money causes binary rounding inaccuracies.*/

/*WHAT HAPPENS IF FK IS MISSING
 *- Referential integrity is not enforced at the database level; the tables would act
 *as isolated tables with no relational validation between them.
 *- This allows "orphan records" (an order referencing a non-existent buyer_id)
 *and permits deleting a parent record while child records still depend on it. */
CREATE TABLE IF NOT EXISTS sellers(
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

CREATE TABLE IF NOT EXISTS buyers(
	buyer_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	name VARCHAR(50) NOT NULL,
	surname VARCHAR(50) NOT NULL,
	address TEXT,
	-- NOT NULL + UNIQUE ensures every buyer has a unique phone number; without it, 
	-- duplicate customer profiles would split order history and distort customer analytics.
	phone_num VARCHAR(20) NOT NULL UNIQUE
);
CREATE TABLE IF NOT EXISTS product_category(
	category_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	-- Prevents duplicate category names and empty labels. Without UNIQUE, products and category
    -- promotions would split across duplicate categories.
	category_name VARCHAR(100) NOT NULL UNIQUE 
);
CREATE TABLE IF NOT EXISTS products(
	product_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	seller_id INT NOT NULL REFERENCES sellers(seller_id),
	category_id INT NOT NULL REFERENCES product_category(category_id),
	-- Added product_name (adjusted from initial logical model) as a unique catalog
    -- prevents duplicate product listings and allows identifying items without parsing descriptions.
	product_name VARCHAR(200) NOT NULL UNIQUE, 
	description TEXT,
	-- NUMERIC(10, 2) guarantees exact decimal arithmetic for currency.
    -- The check constraint Prevents negative prices; without it, negative prices would corrupt order totals and refunds.
	price NUMERIC(10,2) NOT NULL CHECK (price >= 0) 
);
CREATE TABLE IF NOT EXISTS inventory(
	stock_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	product_id INT NOT NULL REFERENCES products(product_id),
	quantity_change INT NOT NULL,
	-- DEFAULT assigns current timestamp when omitted.
    -- Prevents invalid historical/corrupted dates (e.g., 1970-01-01); without it, stock history
    -- and time-series inventory audits would be inaccurate.
	transaction_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP CHECK (transaction_date > '2000-01-01 00:00:00')
);
CREATE TABLE IF NOT EXISTS orders(
	order_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	buyer_id INT NOT NULL REFERENCES buyers(buyer_id),
	-- DEFAULT assigns current timestamp if no date is provided.
    -- Date > January 1, 2000: Prevents invalid pre-2000 order dates.
	order_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP CHECK (order_date > '2000-01-01 00:00:00')
);
CREATE TABLE IF NOT EXISTS order_items(
	order_id INT REFERENCES orders(order_id) NOT NULL,
	product_id INT REFERENCES products(product_id) NOT NULL,
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
CREATE TABLE IF NOT EXISTS payments(
	payment_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	order_id INT NOT NULL REFERENCES orders(order_id),
	-- CONSTRAINT(Non-negative value): Prevents negative payment amounts.
	amount NUMERIC(10, 2) NOT NULL CHECK(amount >= 0), 
	-- CONSTRAINT TYPE 1 (Date > January 1, 2000):
    -- Ensures no pre-2000 payments are recorded; without it, corrupted system dates would break financial reports.
	-- DEFAULT value is the current date and time of the payment
	date_and_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP CHECK (date_and_time > '2000-01-01'), 
    -- Restricts status to four valid states; without it, typos or invalid strings (e.g., 'paid')
    -- would break payment tracking and status filtering.
	status VARCHAR(50) NOT NULL CHECK (status IN ('Pending', 'Completed', 'Failed', 'Refunded')) 
);
CREATE TABLE IF NOT EXISTS deliveries(
	delivery_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	order_id INT NOT NULL REFERENCES orders(order_id),
	-- Restricts delivery status to four valid states; without it, inconsistent status labels
    -- would disrupt order fulfillment workflows.
	status VARCHAR(50) NOT NULL CHECK (status IN ('Processing', 'Shipped', 'Delivered', 'Canceled')), 
	-- DEFAULT assigns current timestamp if no date is provided.
	date_changed TIMESTAMP DEFAULT CURRENT_TIMESTAMP 
);

CREATE TABLE IF NOT EXISTS reviews(
	review_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	buyer_id INT NOT NULL REFERENCES buyers(buyer_id),
	product_id INT NOT NULL REFERENCES products(product_id),
	-- INT is required to calculate average product ratings, CHECK restricts values to 1-5 stars.
    -- Without this CHECK, out-of-range ratings would skew average product scores.
	rating INT NOT NULL CHECK(rating >= 1 AND rating <= 5), 
	-- TEXT is used because review length is unpredictable free-form text.
	review_text TEXT,
	-- if no date provided, current date is assigned to the field
	review_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP, 
	-- The composite unique ensures one buyer can submit only one review per product; without it, a user could spam
    -- multiple reviews and artificially manipulate a product's rating.
	UNIQUE(buyer_id, product_id) 
);
CREATE TABLE IF NOT EXISTS discounts (
	discount_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	product_id INT NOT NULL REFERENCES products(product_id),
	-- Prevents zero or negative discounts, without it, a negative discount would mistakenly increase the price.
	discount_amount NUMERIC(10, 2) NOT NULL CHECK(discount_amount > 0),
	start_date TIMESTAMP NOT NULL CHECK (start_date > '2000-01-01 00:00:00'),
	end_date TIMESTAMP NOT NULL,
	-- Ensures logical date interval, without it, a discount could end before it starts.
	CHECK(end_date > start_date) 
);
CREATE TABLE IF NOT EXISTS promotions (
	promotion_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	category_id INT NOT NULL REFERENCES product_category(category_id),
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


INSERT INTO sellers (name, surname, company_name, address, phone_num)
VALUES
    ('Nikolay', 'Mravov', 'Solaria EOOD', 'Sliven, Industrial Zone, ul. Samuilovsko Shose 12', '+359887412589'),
    ('Radinela', 'Mravova', 'Aura Beauty Lab', 'Sofia, kv. Lozenets, ul. Zlatovrah 34', '+359889632147')
ON CONFLICT (phone_num) DO NOTHING;


INSERT INTO buyers (name, surname, address, phone_num)
VALUES
    ('Yuliyana', 'Mravova', 'Sofia, Studentski Grad, bl. 59', '+359895147258'),
    ('Zlatina', 'Vasileva', 'Stara Zagora, bul. Tsar Simeon Veliki 104', '+359896369852')
ON CONFLICT (phone_num) DO NOTHING;


INSERT INTO product_category (category_name)
VALUES
    ('Cleaning & Disinfectants'),
    ('Skincare & Cosmetics')
ON CONFLICT (category_name) DO NOTHING;


INSERT INTO products (seller_id, category_id, product_name, description, price)
SELECT
    s.seller_id,
    c.category_id,
    'Solaria Multi-Surface Disinfectant 5L',
    'Professional bactericidal surface cleaner and disinfectant for home and industrial use',
    24.80
FROM sellers s
CROSS JOIN product_category c
WHERE s.phone_num = '+359887412589'
  AND c.category_name = 'Cleaning & Disinfectants'
ON CONFLICT (product_name) DO NOTHING;

INSERT INTO products (seller_id, category_id, product_name, description, price)
SELECT
    s.seller_id,
    c.category_id,
    'Azelaic Acid & Niacinamide Balancing Serum 30ml',
    'Daily soothing serum for combination skin with 10% azelaic acid and vitamin B3',
    32.50
FROM sellers s
CROSS JOIN product_category c
WHERE s.phone_num = '+359889632147'
  AND c.category_name = 'Skincare & Cosmetics'
ON CONFLICT (product_name) DO NOTHING;


INSERT INTO inventory (product_id, quantity_change, transaction_date)
SELECT
    p.product_id,
    120,
    '2026-10-05 09:30:00'
FROM products p
WHERE p.product_name = 'Solaria Multi-Surface Disinfectant 5L'
  AND NOT EXISTS (
      SELECT 1 FROM inventory i
      WHERE i.product_id = p.product_id AND i.transaction_date = '2026-10-05 09:30:00'
  );

INSERT INTO inventory (product_id, quantity_change, transaction_date)
SELECT
    p.product_id,
    45,
    '2026-10-06 11:15:00'
FROM products p
WHERE p.product_name = 'Azelaic Acid & Niacinamide Balancing Serum 30ml'
  AND NOT EXISTS (
      SELECT 1 FROM inventory i
      WHERE i.product_id = p.product_id AND i.transaction_date = '2026-10-06 11:15:00'
  );


INSERT INTO orders (buyer_id, order_date)
SELECT
    b.buyer_id,
    '2026-10-20 13:40:00'
FROM buyers b
WHERE b.phone_num = '+359895147258'
  AND NOT EXISTS (
      SELECT 1 FROM orders o
      WHERE o.buyer_id = b.buyer_id AND o.order_date = '2026-10-20 13:40:00'
  );

INSERT INTO orders (buyer_id, order_date)
SELECT
    b.buyer_id,
    '2026-10-22 17:10:00'
FROM buyers b
WHERE b.phone_num = '+359896369852'
  AND NOT EXISTS (
      SELECT 1 FROM orders o
      WHERE o.buyer_id = b.buyer_id AND o.order_date = '2026-10-22 17:10:00'
  );


INSERT INTO order_items (order_id, product_id, quantity, price_at_purchase)
SELECT
    o.order_id,
    p.product_id,
    2,
    p.price
FROM orders o
CROSS JOIN products p
WHERE o.order_date = '2026-10-20 13:40:00'
  AND p.product_name = 'Solaria Multi-Surface Disinfectant 5L'
ON CONFLICT (order_id, product_id) DO NOTHING;

INSERT INTO order_items (order_id, product_id, quantity, price_at_purchase)
SELECT
    o.order_id,
    p.product_id,
    1,
    p.price
FROM orders o
CROSS JOIN products p
WHERE o.order_date = '2026-10-22 17:10:00'
  AND p.product_name = 'Azelaic Acid & Niacinamide Balancing Serum 30ml'
ON CONFLICT (order_id, product_id) DO NOTHING;


INSERT INTO payments (order_id, amount, date_and_time, status)
SELECT
    o.order_id,
    49.60,
    '2026-10-20 13:42:00',
    'Completed'
FROM orders o
WHERE o.order_date = '2026-10-20 13:40:00'
  AND NOT EXISTS (
      SELECT 1 FROM payments pay WHERE pay.order_id = o.order_id
  );

INSERT INTO payments (order_id, amount, date_and_time, status)
SELECT
    o.order_id,
    32.50,
    '2026-10-22 17:15:00',
    'Pending'
FROM orders o
WHERE o.order_date = '2026-10-22 17:10:00'
  AND NOT EXISTS (
      SELECT 1 FROM payments pay WHERE pay.order_id = o.order_id
  );

-- 9. deliveries (2 rows)
INSERT INTO deliveries (order_id, status, date_changed)
SELECT
    o.order_id,
    'Delivered',
    '2026-10-23 10:20:00'
FROM orders o
WHERE o.order_date = '2026-10-20 13:40:00'
  AND NOT EXISTS (
      SELECT 1 FROM deliveries d WHERE d.order_id = o.order_id
  );

INSERT INTO deliveries (order_id, status, date_changed)
SELECT
    o.order_id,
    'Shipped',
    '2026-10-24 15:05:00'
FROM orders o
WHERE o.order_date = '2026-10-22 17:10:00'
  AND NOT EXISTS (
      SELECT 1 FROM deliveries d WHERE d.order_id = o.order_id
  );


INSERT INTO reviews (buyer_id, product_id, rating, review_text, review_date)
SELECT
    b.buyer_id,
    p.product_id,
    5,
    'Very effective cleaner with a fresh scent, great value for a 5L canister.',
    '2026-10-25 19:30:00'
FROM buyers b
CROSS JOIN products p
WHERE b.phone_num = '+359895147258'
  AND p.product_name = 'Solaria Multi-Surface Disinfectant 5L'
ON CONFLICT (buyer_id, product_id) DO NOTHING;

INSERT INTO reviews (buyer_id, product_id, rating, review_text, review_date)
SELECT
    b.buyer_id,
    p.product_id,
    5,
    'Lightweight texture, absorbs quickly and calms redness within a few days.',
    '2026-10-26 14:15:00'
FROM buyers b
CROSS JOIN products p
WHERE b.phone_num = '+359896369852'
  AND p.product_name = 'Azelaic Acid & Niacinamide Balancing Serum 30ml'
ON CONFLICT (buyer_id, product_id) DO NOTHING;


INSERT INTO discounts (product_id, discount_amount, start_date, end_date)
SELECT
    p.product_id,
    4.80,
    '2026-11-01 00:00:00',
    '2026-11-30 23:59:59'
FROM products p
WHERE p.product_name = 'Solaria Multi-Surface Disinfectant 5L'
  AND NOT EXISTS (
      SELECT 1 FROM discounts d
      WHERE d.product_id = p.product_id AND d.start_date = '2026-11-01 00:00:00'
  );

INSERT INTO discounts (product_id, discount_amount, start_date, end_date)
SELECT
    p.product_id,
    5.00,
    '2026-11-10 00:00:00',
    '2026-11-25 23:59:59'
FROM products p
WHERE p.product_name = 'Azelaic Acid & Niacinamide Balancing Serum 30ml'
  AND NOT EXISTS (
      SELECT 1 FROM discounts d
      WHERE d.product_id = p.product_id AND d.start_date = '2026-11-10 00:00:00'
  );


INSERT INTO promotions (category_id, promotion_percent, start_date, end_date)
SELECT
    c.category_id,
    15.00,
    '2026-11-15 00:00:00',
    '2026-11-30 23:59:59'
FROM product_category c
WHERE c.category_name = 'Cleaning & Disinfectants'
  AND NOT EXISTS (
      SELECT 1 FROM promotions pr
      WHERE pr.category_id = c.category_id AND pr.start_date = '2026-11-15 00:00:00'
  );

INSERT INTO promotions (category_id, promotion_percent, start_date, end_date)
SELECT
    c.category_id,
    20.00,
    '2026-11-20 00:00:00',
    '2026-12-05 23:59:59'
FROM product_category c
WHERE c.category_name = 'Skincare & Cosmetics'
  AND NOT EXISTS (
      SELECT 1 FROM promotions pr
      WHERE pr.category_id = c.category_id AND pr.start_date = '2026-11-20 00:00:00'
  );


ALTER TABLE sellers          ADD COLUMN IF NOT EXISTS record_ts DATE NOT NULL DEFAULT CURRENT_DATE;
ALTER TABLE buyers           ADD COLUMN IF NOT EXISTS record_ts DATE NOT NULL DEFAULT CURRENT_DATE;
ALTER TABLE product_category ADD COLUMN IF NOT EXISTS record_ts DATE NOT NULL DEFAULT CURRENT_DATE;
ALTER TABLE products         ADD COLUMN IF NOT EXISTS record_ts DATE NOT NULL DEFAULT CURRENT_DATE;
ALTER TABLE inventory        ADD COLUMN IF NOT EXISTS record_ts DATE NOT NULL DEFAULT CURRENT_DATE;
ALTER TABLE orders           ADD COLUMN IF NOT EXISTS record_ts DATE NOT NULL DEFAULT CURRENT_DATE;
ALTER TABLE order_items      ADD COLUMN IF NOT EXISTS record_ts DATE NOT NULL DEFAULT CURRENT_DATE;
ALTER TABLE payments         ADD COLUMN IF NOT EXISTS record_ts DATE NOT NULL DEFAULT CURRENT_DATE;
ALTER TABLE deliveries       ADD COLUMN IF NOT EXISTS record_ts DATE NOT NULL DEFAULT CURRENT_DATE;
ALTER TABLE reviews          ADD COLUMN IF NOT EXISTS record_ts DATE NOT NULL DEFAULT CURRENT_DATE;
ALTER TABLE discounts        ADD COLUMN IF NOT EXISTS record_ts DATE NOT NULL DEFAULT CURRENT_DATE;
ALTER TABLE promotions       ADD COLUMN IF NOT EXISTS record_ts DATE NOT NULL DEFAULT CURRENT_DATE;

SELECT 'sellers' AS table_name, COUNT(*) AS rows_count, COUNT(record_ts) AS record_ts_filled, MIN(record_ts) AS sample_date FROM sellers
UNION ALL SELECT 'buyers',           COUNT(*), COUNT(record_ts), MIN(record_ts) FROM buyers
UNION ALL SELECT 'product_category', COUNT(*), COUNT(record_ts), MIN(record_ts) FROM product_category
UNION ALL SELECT 'products',         COUNT(*), COUNT(record_ts), MIN(record_ts) FROM products
UNION ALL SELECT 'inventory',        COUNT(*), COUNT(record_ts), MIN(record_ts) FROM inventory
UNION ALL SELECT 'orders',           COUNT(*), COUNT(record_ts), MIN(record_ts) FROM orders
UNION ALL SELECT 'order_items',      COUNT(*), COUNT(record_ts), MIN(record_ts) FROM order_items
UNION ALL SELECT 'payments',         COUNT(*), COUNT(record_ts), MIN(record_ts) FROM payments
UNION ALL SELECT 'deliveries',       COUNT(*), COUNT(record_ts), MIN(record_ts) FROM deliveries
UNION ALL SELECT 'reviews',          COUNT(*), COUNT(record_ts), MIN(record_ts) FROM reviews
UNION ALL SELECT 'discounts',        COUNT(*), COUNT(record_ts), MIN(record_ts) FROM discounts
UNION ALL SELECT 'promotions',       COUNT(*), COUNT(record_ts), MIN(record_ts) FROM promotions
ORDER BY table_name;



