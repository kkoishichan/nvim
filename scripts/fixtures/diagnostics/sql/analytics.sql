-- Analytics reporting sample with deliberate diagnostics (sqruff, PostgreSQL dialect).
--
-- Intended findings:
--   CP01 inconsistent keyword capitalisation, LT01 spacing, LT02 indentation,
--   AL01/AL02 aliasing without AS, AM04 SELECT *, RF02 unqualified column references in joins,
--   ST06 select target order, LT05 line length, CV03 trailing comma, parse errors (PRS).

CREATE TABLE customers (
    id bigserial PRIMARY KEY,
    email text NOT NULL UNIQUE,
    country_code char(2) NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    tier text NOT NULL DEFAULT 'free'
);

CREATE TABLE orders (
    id bigserial PRIMARY KEY,
    customer_id bigint NOT NULL REFERENCES customers (id),
    status text NOT NULL,
    total_cents integer NOT NULL,
    currency char(3) NOT NULL DEFAULT 'EUR',
    placed_at timestamptz NOT NULL DEFAULT now(),
    shipped_at timestamptz
);

CREATE TABLE order_items (
    order_id bigint NOT NULL REFERENCES orders (id),
    sku text NOT NULL,
    quantity integer NOT NULL CHECK (quantity > 0),
    unit_cents integer NOT NULL,
    PRIMARY KEY (order_id, sku)
);

CREATE INDEX orders_customer_idx ON orders (customer_id, placed_at DESC);
CREATE INDEX orders_status_idx ON orders (status) WHERE status <> 'cancelled';

-- Daily revenue per country.
select c.country_code, date_trunc('day', o.placed_at) as day, sum(o.total_cents) AS revenue_cents
from orders o
join customers c on c.id = o.customer_id
where o.status in ('paid', 'shipped')
GROUP BY c.country_code, date_trunc('day', o.placed_at)
order by day desc, revenue_cents desc;

-- Top customers in the last 90 days.
SELECT *
FROM (
    SELECT customer_id, COUNT(*) AS order_count, SUM(total_cents) AS spent_cents
    FROM orders
    WHERE placed_at >= now() - interval '90 days' AND status <> 'cancelled'
    GROUP BY customer_id
) top
JOIN customers ON customers.id = top.customer_id
ORDER BY spent_cents DESC
LIMIT 20;

-- Average basket size per tier, with a very long line that the layout rules will flag because it keeps going well past the configured maximum width.
SELECT customers.tier, AVG(order_items.quantity * order_items.unit_cents) AS avg_line_cents, COUNT(DISTINCT orders.id) AS orders_counted
FROM order_items
JOIN orders ON orders.id = order_items.order_id
JOIN customers ON customers.id = orders.customer_id
GROUP BY customers.tier;

-- Orders waiting for shipment, ordered by age.
SELECT
    id,
    customer_id,
    placed_at,
    now() - placed_at AS waiting
  FROM orders
 WHERE status = 'paid'
   AND shipped_at IS NULL
 ORDER BY placed_at;

-- Monthly cohort retention.
WITH first_orders AS (
    SELECT customer_id, MIN(placed_at) AS first_at
    FROM orders
    GROUP BY customer_id
),
activity AS (
    SELECT
        o.customer_id,
        date_trunc('month', f.first_at) AS cohort,
        date_trunc('month', o.placed_at) AS active_month
    FROM orders o
    JOIN first_orders f ON f.customer_id = o.customer_id
)
SELECT
    cohort,
    active_month,
    COUNT(DISTINCT customer_id) AS customers
FROM activity
GROUP BY cohort, active_month
ORDER BY cohort, active_month;

-- Items that were never ordered twice.
SELECT sku,COUNT(*) AS times
FROM order_items
GROUP BY sku
HAVING COUNT(*)=1;

-- Shipping delay distribution.
SELECT
    width_bucket(EXTRACT(epoch FROM (shipped_at - placed_at)) / 3600, 0, 240, 10) AS bucket,
    COUNT(*) AS orders,
FROM orders
WHERE shipped_at IS NOT NULL
GROUP BY bucket
ORDER BY bucket;

-- Customers without orders.
SELECT customers.id, customers.email
FROM customers
LEFT JOIN orders ON orders.customer_id = customers.id
WHERE orders.id IS NULL;

-- Currency breakdown with inconsistent capitalisation inside one statement.
Select currency, Count(*) as orders, SUM(total_cents) As total
FROM orders
Group By currency
ORDER by total DESC;

-- Mark stale paid orders as needing review.
UPDATE orders
SET status = 'review'
WHERE status = 'paid'
  AND shipped_at IS NULL
  AND placed_at < now() - interval '14 days';

-- Delete abandoned carts older than a year.
DELETE FROM orders
WHERE status = 'cart' AND placed_at < now() - interval '1 year';

-- Materialised summary.
CREATE MATERIALIZED VIEW daily_summary AS
SELECT
    date_trunc('day', placed_at) AS day,
    COUNT(*) AS orders,
    SUM(total_cents) AS revenue_cents,
    COUNT(DISTINCT customer_id) AS customers
FROM orders
WHERE status <> 'cancelled'
GROUP BY date_trunc('day', placed_at);

-- A statement with a typo in the keyword, left for the parser.
SELEC id, email FROM customers WHERE tier = 'enterprise';

-- Unbalanced parenthesis, also left for the parser.
SELECT COUNT(*) FROM orders WHERE (status = 'paid' OR status = 'shipped';

-- Function to compute lifetime value.
CREATE OR REPLACE FUNCTION lifetime_value(p_customer bigint)
RETURNS bigint
LANGUAGE sql
STABLE
AS $$
    SELECT COALESCE(SUM(total_cents), 0)
    FROM orders
    WHERE customer_id = p_customer AND status IN ('paid', 'shipped');
$$;

-- Refresh helper.
CREATE OR REPLACE FUNCTION refresh_summary()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    REFRESH MATERIALIZED VIEW daily_summary;
END;
$$;

-- Final report joining everything.
SELECT
    c.email,
    c.tier,
    lifetime_value(c.id) AS ltv_cents,
    (SELECT COUNT(*) FROM orders o WHERE o.customer_id = c.id) AS orders,
    (SELECT MAX(placed_at) FROM orders o WHERE o.customer_id = c.id) AS last_order
FROM customers c
WHERE lifetime_value(c.id) > 100000
ORDER BY ltv_cents DESC;
