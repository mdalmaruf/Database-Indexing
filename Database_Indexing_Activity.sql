-- Database Indexing Activity: all SQL in the order of the handout
-- Run one block at a time (select it and press Ctrl+Shift+Enter in Workbench).


-- ==================================================================
-- Step 1. Build the database
-- ==================================================================

-- 1a. The database and the recursion limit

DROP DATABASE IF EXISTS maplemart_index;
CREATE DATABASE maplemart_index;
USE maplemart_index;
SET SESSION cte_max_recursion_depth = 1000000;

-- Try this: in a new connection, run USE maplemart_index; and block 1b without
-- the SET line above. You get ERROR 3636 (recursion limit of 1,000).

-- 1b. A table of numbers

CREATE TABLE seq (n INT PRIMARY KEY);

INSERT INTO seq (n)
WITH RECURSIVE s (n) AS (
  SELECT 1
  UNION ALL
  SELECT n + 1 FROM s WHERE n < 200000
)
SELECT n FROM s;

-- 1c. Customers (20,000 rows)

CREATE TABLE customers (
  customer_id INT PRIMARY KEY,
  email       VARCHAR(100) NOT NULL,
  full_name   VARCHAR(60)  NOT NULL,
  city        VARCHAR(30)  NOT NULL,
  province    CHAR(2)      NOT NULL,
  segment     VARCHAR(15)  NOT NULL,
  created_at  DATETIME     NOT NULL
);

INSERT INTO customers
SELECT n,
       CONCAT(ELT(1 + n % 12, 'maria', 'li', 'arjun', 'fatima',
                              'noah', 'emma', 'omar', 'sofia',
                              'liam', 'aisha', 'chen', 'olivia'),
              '.', n, '@',
              ELT(1 + (n DIV 7) % 4, 'gmail.com', 'outlook.com',
                                     'yahoo.ca', 'algomau.ca')),
       CONCAT(ELT(1 + n % 12, 'Maria', 'Li', 'Arjun', 'Fatima',
                              'Noah', 'Emma', 'Omar', 'Sofia',
                              'Liam', 'Aisha', 'Chen', 'Olivia'),
              ' ',
              ELT(1 + (n DIV 12) % 10, 'Chen', 'Singh', 'Ahmed', 'Tremblay',
                                       'Smith', 'Nguyen', 'Brown', 'Khan',
                                       'Roy', 'Wilson')),
       ELT(1 + (n * 7) % 8, 'Toronto', 'Brampton', 'Ottawa', 'Montreal',
                            'Halifax', 'Calgary', 'Vancouver', 'Winnipeg'),
       ELT(1 + (n * 7) % 8, 'ON', 'ON', 'ON', 'QC', 'NS', 'AB', 'BC', 'MB'),
       ELT(1 + (n * 13) % 10, 'Consumer', 'Consumer', 'Consumer', 'Consumer',
                              'Consumer', 'Consumer', 'Consumer',
                              'Student', 'Student', 'Business'),
       '2021-01-01' + INTERVAL (n * 37) % 1700 DAY
FROM seq
WHERE n <= 20000;

-- 1d. Products (2,000 rows)

CREATE TABLE products (
  product_id INT PRIMARY KEY,
  sku        CHAR(10)      NOT NULL,
  name       VARCHAR(60)   NOT NULL,
  category   VARCHAR(20)   NOT NULL,
  price      DECIMAL(8,2)  NOT NULL,
  stock      INT           NOT NULL
);

INSERT INTO products
SELECT n,
       CONCAT('SKU', LPAD(n, 7, '0')),
       CONCAT(ELT(1 + n % 4, 'Electronics', 'Home', 'Grocery', 'Apparel'),
              ' item ', n),
       ELT(1 + n % 4, 'Electronics', 'Home', 'Grocery', 'Apparel'),
       ROUND(ELT(1 + n % 4, 60, 25, 4, 15) * (1 + (n * 31) % 40 / 4), 2),
       (n * 17) % 500
FROM seq
WHERE n <= 2000;

-- 1e. Orders (200,000 rows)

CREATE TABLE orders (
  order_id     INT PRIMARY KEY,
  customer_id  INT           NOT NULL,
  store_id     TINYINT       NOT NULL,
  order_date   DATETIME      NOT NULL,
  status       VARCHAR(12)   NOT NULL,
  total_amount DECIMAL(10,2) NOT NULL
);

INSERT INTO orders
SELECT n,
       1 + CRC32(CONCAT('c', n)) % 20000,
       1 + (n * 11) % 9,
       '2024-01-01' + INTERVAL FLOOR(n * 315.792) SECOND,
       CASE WHEN CRC32(CONCAT('s', n)) % 100 < 80 THEN 'DELIVERED'
            WHEN CRC32(CONCAT('s', n)) % 100 < 89 THEN 'SHIPPED'
            WHEN CRC32(CONCAT('s', n)) % 100 < 97 THEN 'PENDING'
            ELSE 'CANCELLED' END,
       0                                   -- filled in by step 1g
FROM seq;

-- 1f. Order lines (about 500,000 rows)

CREATE TABLE order_items (
  item_id    INT AUTO_INCREMENT PRIMARY KEY,
  order_id   INT          NOT NULL,
  product_id INT          NOT NULL,
  quantity   SMALLINT     NOT NULL,
  unit_price DECIMAL(8,2) NOT NULL
);

INSERT INTO order_items (order_id, product_id, quantity, unit_price)
SELECT o.order_id,
       p.product_id,
       1 + (o.order_id + k.k) % 3,
       p.price
FROM orders o
JOIN (SELECT 1 AS k UNION ALL SELECT 2
      UNION ALL SELECT 3 UNION ALL SELECT 4) k
  ON k.k <= 1 + o.order_id % 4             -- 1 to 4 lines per order
JOIN products p
  ON p.product_id = 1 + (o.order_id * 7 + k.k * 131) % 2000;

-- 1g. Totals, clean-up and statistics

UPDATE orders o
JOIN (SELECT order_id, SUM(quantity * unit_price) AS t
      FROM order_items
      GROUP BY order_id) s
  ON s.order_id = o.order_id
SET o.total_amount = s.t;

DROP TABLE seq;

ANALYZE TABLE customers, products, orders, order_items;

-- 1h. Check the row counts

SELECT 'customers' AS tbl, COUNT(*) AS row_count FROM customers
UNION ALL SELECT 'products',    COUNT(*) FROM products
UNION ALL SELECT 'orders',      COUNT(*) FROM orders
UNION ALL SELECT 'order_items', COUNT(*) FROM order_items;

-- Try this: look at the generated data

SELECT * FROM orders LIMIT 5;

SHOW INDEX FROM orders;


-- ==================================================================
-- Step 2. Ask MySQL how it runs the slow query
-- ==================================================================

SELECT order_id, order_date, status, total_amount
FROM orders
WHERE customer_id = 4242
ORDER BY order_date DESC
LIMIT 20;

EXPLAIN
SELECT order_id, order_date, status, total_amount
FROM orders
WHERE customer_id = 4242
ORDER BY order_date DESC
LIMIT 20;

EXPLAIN ANALYZE
SELECT order_id, order_date, status, total_amount
FROM orders
WHERE customer_id = 4242
ORDER BY order_date DESC
LIMIT 20;

-- Why is reading every row slow?

-- Try this: a customer with more orders

SELECT customer_id, COUNT(*) AS orders
FROM orders
GROUP BY customer_id
ORDER BY orders DESC
LIMIT 3;

EXPLAIN
SELECT order_id, order_date, status, total_amount
FROM orders
WHERE customer_id = 5572
ORDER BY order_date DESC
LIMIT 20;


-- ==================================================================
-- Step 3. Add an index
-- ==================================================================

CREATE INDEX idx_cust ON orders (customer_id);

EXPLAIN
SELECT order_id, order_date, status, total_amount
FROM orders
WHERE customer_id = 4242
ORDER BY order_date DESC
LIMIT 20;

-- Try this: the index adapts to the customer

EXPLAIN
SELECT order_id, order_date, status, total_amount
FROM orders
WHERE customer_id = 5572
ORDER BY order_date DESC
LIMIT 20;

SHOW INDEX FROM orders;


-- ==================================================================
-- Step 4. A composite index: find and sort in one step
-- ==================================================================

DROP INDEX idx_cust ON orders;
CREATE INDEX idx_cust_date ON orders (customer_id, order_date);

EXPLAIN
SELECT order_id, order_date, status, total_amount
FROM orders
WHERE customer_id = 4242
ORDER BY order_date DESC
LIMIT 20;

EXPLAIN ANALYZE
SELECT order_id, order_date, status, total_amount
FROM orders
WHERE customer_id = 4242
ORDER BY order_date DESC
LIMIT 20;

-- Try this: change the ORDER BY

EXPLAIN
SELECT order_id, order_date, status, total_amount
FROM orders
WHERE customer_id = 4242
ORDER BY order_date ASC
LIMIT 20;

EXPLAIN
SELECT order_id, order_date, status, total_amount
FROM orders
WHERE customer_id = 4242
ORDER BY total_amount DESC
LIMIT 20;

EXPLAIN
SELECT order_id, order_date, status, total_amount
FROM orders
WHERE customer_id = 4242
  AND order_date >= '2025-01-01'
ORDER BY order_date DESC
LIMIT 20;


-- ==================================================================
-- Step 5. A covering index: never touch the table
-- ==================================================================

DROP INDEX idx_cust_date ON orders;
CREATE INDEX idx_cover
  ON orders (customer_id, order_date, status, total_amount);

EXPLAIN
SELECT order_id, order_date, status, total_amount
FROM orders
WHERE customer_id = 4242
ORDER BY order_date DESC
LIMIT 20;

-- Try this: ask for one more column

EXPLAIN
SELECT order_id, order_date, status, total_amount, store_id
FROM orders
WHERE customer_id = 4242
ORDER BY order_date DESC
LIMIT 20;

DROP INDEX idx_cover ON orders;
CREATE INDEX idx_cust_date ON orders (customer_id, order_date);


-- ==================================================================
-- Step 6. When an index does not help
-- ==================================================================

-- 6a. Wrong column (leftmost prefix rule)

EXPLAIN
SELECT COUNT(*) FROM orders
WHERE order_date >= '2025-11-28'
  AND order_date <  '2025-11-29';

CREATE INDEX idx_date ON orders (order_date);

EXPLAIN
SELECT COUNT(*) FROM orders
WHERE order_date >= '2025-11-28'
  AND order_date <  '2025-11-29';

-- 6b. A function on the column

EXPLAIN
SELECT COUNT(*) FROM orders
WHERE YEAR(order_date) = 2025
  AND MONTH(order_date) = 11
  AND DAY(order_date) = 28;

-- 6c. A wildcard at the start

CREATE INDEX idx_email ON customers (email);

EXPLAIN SELECT customer_id, email FROM customers
WHERE email LIKE 'maria.4%';

EXPLAIN SELECT customer_id, email FROM customers
WHERE email LIKE '%@algomau.ca';

-- Try this: when does MySQL give up on an index?

EXPLAIN
SELECT * FROM orders
WHERE order_date >= '2025-11-28'
  AND order_date <  '2025-11-29';

EXPLAIN
SELECT COUNT(*) FROM orders
WHERE order_date >= '2025-11-01'
  AND order_date <  '2025-12-01';

EXPLAIN
SELECT * FROM orders
WHERE order_date >= '2025-01-01';


-- ==================================================================
-- Step 7. Joins need indexes too
-- ==================================================================

EXPLAIN ANALYZE
SELECT o.order_id, o.order_date, p.name, oi.quantity
FROM orders o
JOIN order_items oi ON oi.order_id = o.order_id
JOIN products p     ON p.product_id = oi.product_id
WHERE o.customer_id = 4242;

CREATE INDEX idx_oi_order ON order_items (order_id);

EXPLAIN ANALYZE
SELECT o.order_id, o.order_date, p.name, oi.quantity
FROM orders o
JOIN order_items oi ON oi.order_id = o.order_id
JOIN products p     ON p.product_id = oi.product_id
WHERE o.customer_id = 4242;


-- ==================================================================
-- Step 8. Indexes are not free
-- ==================================================================

-- Try this: hide an index without dropping it

DROP INDEX idx_date ON orders;

ALTER TABLE orders ALTER INDEX idx_cust_date INVISIBLE;
EXPLAIN
SELECT order_id, order_date, status, total_amount
FROM orders
WHERE customer_id = 4242
ORDER BY order_date DESC
LIMIT 20;

ALTER TABLE orders ALTER INDEX idx_cust_date VISIBLE;


-- ==================================================================
-- Your results (hand in)
-- ==================================================================


-- ==================================================================
-- Glossary
-- ==================================================================
