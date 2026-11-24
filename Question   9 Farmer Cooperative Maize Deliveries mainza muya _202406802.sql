* #####################################################################
   QUESTION 9 - Farmer Cooperative Maize Deliveries
   ##################################################################### */
DROP SCHEMA IF EXISTS q9 CASCADE;
CREATE SCHEMA q9;
SET search_path TO q9, public;

-- (a) Tables ------------------------------------------------------------
CREATE TABLE farmers (
    farmer_id     SERIAL PRIMARY KEY,
    farmer_number VARCHAR(20) NOT NULL UNIQUE,
    full_name     VARCHAR(100) NOT NULL
);

CREATE TABLE deliveries (
    delivery_id  SERIAL PRIMARY KEY,
    farmer_id    INTEGER NOT NULL REFERENCES farmers(farmer_id),
    grade        CHAR(1) NOT NULL CHECK (grade IN ('A','B','C')),
    weight_kg    NUMERIC(10,2) NOT NULL,
    unit_rate    NUMERIC(8,2)  NOT NULL,      -- set by trigger
    total_value  NUMERIC(14,2) NOT NULL,      -- set by trigger
    delivered_on DATE NOT NULL,
    is_paid      BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE TABLE daily_purchases (
    purchase_date DATE PRIMARY KEY,
    total_weight  NUMERIC(14,2) NOT NULL DEFAULT 0,
    total_value   NUMERIC(14,2) NOT NULL DEFAULT 0
);

-- (b) Function ----------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_maize_rate(p_grade CHAR)
RETURNS NUMERIC LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
    IF p_grade IS NULL THEN
        RAISE EXCEPTION 'Grade must not be NULL';
    ELSIF p_grade = 'A' THEN RETURN 5.00;
    ELSIF p_grade = 'B' THEN RETURN 4.00;
    ELSIF p_grade = 'C' THEN RETURN 3.00;
    END IF;
    RAISE EXCEPTION 'Unsupported grade: % (use A, B or C)', p_grade;
END $$;

-- (d) Trigger (installed before any data is loaded) ----------------------
CREATE OR REPLACE FUNCTION trg_fn_price_delivery() RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.weight_kg IS NULL OR NEW.weight_kg <= 0 THEN
        RAISE EXCEPTION 'Weight must be positive, got %', NEW.weight_kg;
    END IF;
    NEW.unit_rate   := fn_maize_rate(NEW.grade);
    NEW.total_value := ROUND(NEW.weight_kg * NEW.unit_rate, 2);
    RETURN NEW;
END $$;

CREATE TRIGGER trg_deliveries_price
BEFORE INSERT OR UPDATE ON deliveries
FOR EACH ROW EXECUTE FUNCTION trg_fn_price_delivery();

-- (c) Procedure ---------------------------------------------------------
CREATE OR REPLACE PROCEDURE pr_receive_delivery(p_farmer_id INTEGER, p_grade CHAR,
                                                p_weight NUMERIC, p_date DATE)
LANGUAGE plpgsql AS $$
BEGIN
    PERFORM 1 FROM farmers WHERE farmer_id = p_farmer_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Unknown farmer_id: %', p_farmer_id; END IF;
    IF p_grade IS NULL OR p_grade NOT IN ('A','B','C') THEN
        RAISE EXCEPTION 'Invalid grade: %', p_grade;
    END IF;
    IF p_weight IS NULL OR p_weight <= 0 THEN
        RAISE EXCEPTION 'Weight must be positive, got %', p_weight;
    END IF;
    IF p_date IS NULL THEN RAISE EXCEPTION 'Delivery date must not be NULL'; END IF;

    -- rate and total are filled in by the trigger (placeholders satisfy NOT NULL)
    INSERT INTO deliveries (farmer_id, grade, weight_kg, unit_rate, total_value, delivered_on, is_paid)
    VALUES (p_farmer_id, p_grade, p_weight, 0, 0, p_date, FALSE);
END $$;

-- (a) continued: seed data (direct SQL: trigger supplies rate and value) --
INSERT INTO farmers (farmer_number, full_name) VALUES
 ('F001','Kelvin Musonda'), ('F002','Lillian Chibwe'), ('F003','Moses Kapambwe');

INSERT INTO deliveries (farmer_id, grade, weight_kg, unit_rate, total_value, delivered_on, is_paid) VALUES
 (1,'A', 100, 0, 0, CURRENT_DATE - 3, TRUE),
 (1,'B', 250, 0, 0, CURRENT_DATE - 2, FALSE),
 (2,'C', 400, 0, 0, CURRENT_DATE - 2, TRUE),
 (2,'A',  80, 0, 0, CURRENT_DATE - 1, FALSE),
 (3,'B', 150, 0, 0, CURRENT_DATE - 1, TRUE),
 (3,'C',  60, 0, 0, CURRENT_DATE - 1, TRUE);
CALL pr_receive_delivery(1, 'C', 50, CURRENT_DATE - 1);  -- via the procedure too

SELECT delivery_id, grade, weight_kg, unit_rate, total_value FROM deliveries ORDER BY 1;
-- Rejected: CALL pr_receive_delivery(1,'D',10,CURRENT_DATE); / weight 0 / unknown farmer

-- (e) View --------------------------------------------------------------
CREATE OR REPLACE VIEW v_farmer_amount_due AS
SELECT f.farmer_number, f.full_name,
       COALESCE(SUM(d.total_value) FILTER (WHERE NOT d.is_paid), 0) AS amount_due
FROM farmers f
LEFT JOIN deliveries d ON d.farmer_id = f.farmer_id
GROUP BY f.farmer_id, f.farmer_number, f.full_name;

SELECT * FROM v_farmer_amount_due ORDER BY farmer_number;

-- (f) Index -------------------------------------------------------------
-- Equality column (farmer_id) first, range column (delivered_on) second.
CREATE INDEX idx_deliveries_farmer_date ON deliveries (farmer_id, delivered_on);
ANALYZE deliveries;
SET enable_seqscan = off;
EXPLAIN
SELECT * FROM deliveries
WHERE farmer_id = 1 AND delivered_on BETWEEN CURRENT_DATE - 7 AND CURRENT_DATE;
RESET enable_seqscan;

-- (g) Scheduled job -----------------------------------------------------
CREATE OR REPLACE PROCEDURE pr_refresh_purchases(p_day DATE) LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO daily_purchases (purchase_date, total_weight, total_value)
    SELECT p_day, COALESCE(SUM(weight_kg), 0), COALESCE(SUM(total_value), 0)
    FROM deliveries WHERE delivered_on = p_day
    ON CONFLICT (purchase_date) DO UPDATE
        SET total_weight = EXCLUDED.total_weight, total_value = EXCLUDED.total_value;
END $$;

SELECT cron.schedule('q9_refresh_purchases', '30 1 * * *',
       $$CALL q9.pr_refresh_purchases(CURRENT_DATE - 1)$$);

CALL pr_refresh_purchases(CURRENT_DATE - 1);
CALL pr_refresh_purchases(CURRENT_DATE - 1);             -- replaces, not added again
SELECT * FROM daily_purchases;
