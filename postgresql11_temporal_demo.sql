-- PostgreSQL 11 Temporal Database Demo 
-- Demonstrates:
-- 1. Ordinary table (history lost)
-- 2. Transaction Time via audit trigger
-- 3. Valid Time (several versions per employee, no overlaps)
-- 4. Bitemporal queries: "valid at V, as known at T"
--
-- Conventions used throughout (same as SQL:2011):
-- every period is half-open: [from, to)
-- an open end is 'infinity' (DATE and TIMESTAMP both support it in PostgreSQL)
-- transaction time is assigned by the database, never typed by hand
-- nothing is ever physically removed: a change closes the old row in transaction time (copy to employee_history) and writes a new current row
--
-- Run with autocommit ON (each statement is its own transaction).
-- CURRENT_TIMESTAMP is the transaction start time, so all rows written by one
-- BEGIN ... COMMIT block share one transaction_start ("one change, one timestamp").
-- If the whole file ran inside a single transaction, every version would get the
-- same timestamp and the transaction-time periods would collapse to zero length.

-- Cleanup
DROP VIEW IF EXISTS employee_bitemporal;
DROP TABLE IF EXISTS demo_marks;
DROP TABLE IF EXISTS employee_history;
DROP TABLE IF EXISTS employee CASCADE;
DROP FUNCTION IF EXISTS employee_audit();
DROP FUNCTION IF EXISTS employee_no_overlap();

-- Bookmarks: we record the wall-clock time after each step so that Part 4 can ask
-- "what did the database believe at that moment?" without typing timestamps.
CREATE TABLE demo_marks (
    label      TEXT PRIMARY KEY,
    marked_at  TIMESTAMP NOT NULL
);

-- =====================================================
-- PART 1 - ORDINARY TABLE
-- =====================================================
CREATE TABLE employee (
    employee_id SERIAL PRIMARY KEY,
    employee_name VARCHAR(50) NOT NULL,
    salary NUMERIC(10,2) NOT NULL
);

INSERT INTO employee(employee_name,salary)
VALUES ('Alice',5000),('Bob',4200);

-- Initial state
SELECT * FROM employee;

-- Normal update (history lost)
UPDATE employee
SET salary=5500
WHERE employee_name='Alice';

SELECT * FROM employee;
-- Question: where did Alice's old salary go?
-- Answer: nowhere. The database only knows "now".

-- =====================================================
-- PART 2 - TRANSACTION TIME
-- =====================================================
-- Transaction time = the period during which the database believed a row.
-- The current table keeps only transaction_start: a current row is, by
-- definition, still believed, so its end is 'infinity'.
-- Superseded rows move to employee_history with their transaction_end set.

ALTER TABLE employee
ADD COLUMN transaction_start TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP;

CREATE TABLE employee_history (
    history_id SERIAL PRIMARY KEY,
    employee_id INTEGER NOT NULL,
    employee_name VARCHAR(50) NOT NULL,
    salary NUMERIC(10,2) NOT NULL,
    transaction_start TIMESTAMP NOT NULL,
    transaction_end TIMESTAMP NOT NULL,
    CHECK (transaction_start < transaction_end)   -- no zero-length beliefs
);

-- The audit trigger copies the OLD row (the belief that just ended) into
-- employee_history and stamps the NEW row with the start of its belief.
-- It fires on DELETE too: a physical delete is only the END of a belief,
-- the old row is kept in history ("logical deletion").
CREATE OR REPLACE FUNCTION employee_audit()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO employee_history(
        employee_id,employee_name,salary,
        transaction_start,transaction_end)
    VALUES(
        OLD.employee_id,
        OLD.employee_name,
        OLD.salary,
        OLD.transaction_start,
        CURRENT_TIMESTAMP);

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;

    NEW.transaction_start := CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_employee_audit
BEFORE UPDATE OR DELETE ON employee
FOR EACH ROW
EXECUTE PROCEDURE employee_audit();

INSERT INTO demo_marks VALUES ('part2_start', clock_timestamp());

-- Demonstrate transaction history
UPDATE employee
SET salary=6000
WHERE employee_name='Alice';

INSERT INTO demo_marks VALUES ('alice_6000', clock_timestamp());

SELECT * FROM employee;
SELECT * FROM employee_history;

UPDATE employee
SET salary=6500
WHERE employee_name='Alice';

INSERT INTO demo_marks VALUES ('alice_6500', clock_timestamp());

SELECT * FROM employee;
SELECT * FROM employee_history;
-- Question: Alice's row has moved to history twice, but with different periods.
-- Which row was believed between the marks alice_6000 and alice_6500?

-- Rollback query: the table as the database believed it at a past moment.
-- A row was believed at T when transaction_start <= T < transaction_end.
SELECT employee_name, salary, transaction_start, transaction_end
FROM (
    SELECT employee_name, salary, transaction_start,
           TIMESTAMP 'infinity' AS transaction_end
    FROM employee
    UNION ALL
    SELECT employee_name, salary, transaction_start, transaction_end
    FROM employee_history
) AS all_beliefs
WHERE transaction_start <= (SELECT marked_at FROM demo_marks WHERE label='alice_6000')
  AND (SELECT marked_at FROM demo_marks WHERE label='alice_6000') < transaction_end
ORDER BY employee_name;
-- Expected: Alice 6000, Bob 4200.

-- =====================================================
-- PART 3 - VALID TIME
-- =====================================================
-- Valid time = the period during which a fact is true in the real world.
-- It is supplied by the user and may lie in the past or in the future.
--
-- Two consequences:
-- (a) a raise "effective 1 May" does not REPLACE the old salary: the old salary
--     stays valid until 1 May, so ONE employee needs SEVERAL current rows;
-- (b) therefore employee_id can no longer be the primary key on its own.
--     The key becomes (employee_id, valid_from), and the valid periods of one
--     employee must never overlap.

ALTER TABLE employee
ADD COLUMN valid_from DATE NOT NULL DEFAULT DATE '2025-01-01',
ADD COLUMN valid_to   DATE NOT NULL DEFAULT DATE 'infinity',
ADD CONSTRAINT employee_valid_period CHECK (valid_from < valid_to);

-- Before this point the table had no valid time: every fact was implicitly
-- "valid since the start of our records, until further notice". Make that
-- explicit for the rows already in history so that no period is left NULL.
-- (This is a one-off schema migration, not a change of belief, so it is done
-- in place and not audited.)
ALTER TABLE employee_history
ADD COLUMN valid_from DATE,
ADD COLUMN valid_to   DATE;

UPDATE employee_history
SET valid_from = DATE '2025-01-01',
    valid_to   = DATE 'infinity'
WHERE valid_from IS NULL;

ALTER TABLE employee_history
ALTER COLUMN valid_from SET NOT NULL,
ALTER COLUMN valid_to   SET NOT NULL,
ADD CONSTRAINT employee_history_valid_period CHECK (valid_from < valid_to);

-- New employees hired from now on are valid from today unless stated otherwise.
ALTER TABLE employee
ALTER COLUMN valid_from SET DEFAULT CURRENT_DATE;

-- Several versions per employee: change the primary key.
-- employee_id keeps its SERIAL default for NEW employees; a new VERSION of an
-- existing employee is inserted with an explicit employee_id.
ALTER TABLE employee DROP CONSTRAINT employee_pkey;
ALTER TABLE employee ADD PRIMARY KEY (employee_id, valid_from);

-- The audit trigger now carries the valid period of the ended belief as well.
CREATE OR REPLACE FUNCTION employee_audit()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO employee_history(
        employee_id,employee_name,salary,
        transaction_start,transaction_end,
        valid_from,valid_to)
    VALUES(
        OLD.employee_id,
        OLD.employee_name,
        OLD.salary,
        OLD.transaction_start,
        CURRENT_TIMESTAMP,
        OLD.valid_from,
        OLD.valid_to);

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;

    NEW.transaction_start := CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$;

-- Temporal primary key: at any instant an employee has at most one salary.
-- (A declarative alternative is an EXCLUDE constraint with daterange and the
-- btree_gist extension; the trigger needs no extension but, unlike the
-- constraint, is not safe against two concurrent sessions.)
CREATE OR REPLACE FUNCTION employee_no_overlap()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    self_from DATE := NULL;      -- the row being updated must not clash with itself
    clash     employee%ROWTYPE;
BEGIN
    IF TG_OP = 'UPDATE' THEN
        self_from := OLD.valid_from;
    END IF;

    SELECT e.* INTO clash
    FROM employee e
    WHERE e.employee_id = NEW.employee_id
      AND e.valid_from  < NEW.valid_to          -- periods overlap
      AND NEW.valid_from < e.valid_to
      AND (self_from IS NULL OR e.valid_from <> self_from)
    LIMIT 1;

    IF FOUND THEN
        RAISE EXCEPTION 'employee % already has salary % valid in [%, %); [%, %) overlaps it',
            NEW.employee_id, clash.salary, clash.valid_from, clash.valid_to,
            NEW.valid_from, NEW.valid_to;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_employee_no_overlap
BEFORE INSERT OR UPDATE OF employee_id, valid_from, valid_to ON employee
FOR EACH ROW
EXECUTE PROCEDURE employee_no_overlap();

INSERT INTO demo_marks VALUES ('part3_start', clock_timestamp());

SELECT * FROM employee ORDER BY employee_id, valid_from;
-- Alice 6500 and Bob 4200, both valid [2025-01-01, infinity).

-- -----------------------------------------------------
-- 3a. A raise effective on a date: close the old period, open a new one
-- -----------------------------------------------------
-- Alice gets 7000 effective 2025-05-01. Her 6500 stays valid until then.
-- Both statements belong to ONE change, so they share one transaction_start.
BEGIN;

UPDATE employee
SET valid_to = DATE '2025-05-01'
WHERE employee_name='Alice'
  AND valid_to = DATE 'infinity';

INSERT INTO employee(employee_id,employee_name,salary,valid_from,valid_to)
SELECT employee_id,'Alice',7000,DATE '2025-05-01',DATE 'infinity'
FROM employee
WHERE employee_name='Alice'
  AND valid_from = DATE '2025-01-01';

COMMIT;

INSERT INTO demo_marks VALUES ('alice_raise', clock_timestamp());

SELECT * FROM employee ORDER BY employee_id, valid_from;
SELECT * FROM employee_history ORDER BY history_id;
-- Question: why does history now hold "6500 valid [2025-01-01, infinity)"?
-- Answer: that was the belief until the raise was recorded. It is not wrong
-- history, it is a belief that was superseded (closed in transaction time).

-- -----------------------------------------------------
-- 3b. Late entry: a fact recorded after it became true
-- -----------------------------------------------------
INSERT INTO employee(employee_name,salary,valid_from)
VALUES ('Carol',4500,DATE '2025-01-01');

INSERT INTO demo_marks VALUES ('carol_hired', clock_timestamp());

-- Later HR discovers Carol should have earned 4800 since March 1.
-- Recorded today, valid since 2025-03-01: 4500 remains valid for Jan-Feb.
BEGIN;

UPDATE employee
SET valid_to = DATE '2025-03-01'
WHERE employee_name='Carol'
  AND valid_to = DATE 'infinity';

INSERT INTO employee(employee_id,employee_name,salary,valid_from,valid_to)
SELECT employee_id,'Carol',4800,DATE '2025-03-01',DATE 'infinity'
FROM employee
WHERE employee_name='Carol'
  AND valid_from = DATE '2025-01-01';

COMMIT;

INSERT INTO demo_marks VALUES ('carol_4800', clock_timestamp());

SELECT * FROM employee ORDER BY employee_id, valid_from;

-- -----------------------------------------------------
-- 3c. Correction of a wrong date: the raise was effective April 1, not March 1
-- -----------------------------------------------------
-- The overlap trigger forces the right order: shrink first, then extend.
-- Extending the 4500 row first would overlap the 4800 row and is rejected:
DO $$
BEGIN
    UPDATE employee
    SET valid_to = DATE '2025-04-01'
    WHERE employee_name='Carol' AND valid_from = DATE '2025-01-01';
    RAISE NOTICE 'this should not be reached';
EXCEPTION WHEN raise_exception THEN
    RAISE NOTICE 'rejected as expected: %', SQLERRM;
END;
$$;

-- (The rejected statement was rolled back, including the history row the audit
-- trigger had already written. Sequences are not transactional, so history_id 5
-- is skipped from here on: a gap in the ids, not a gap in the history.)

-- Correct order: move the start of the 4800 row forward (leaves a gap),
-- then extend the 4500 row into the gap. One change, one transaction.
BEGIN;

UPDATE employee
SET valid_from = DATE '2025-04-01'
WHERE employee_name='Carol' AND valid_from = DATE '2025-03-01';

UPDATE employee
SET valid_to = DATE '2025-04-01'
WHERE employee_name='Carol' AND valid_from = DATE '2025-01-01';

COMMIT;

INSERT INTO demo_marks VALUES ('carol_date_fixed', clock_timestamp());

SELECT * FROM employee ORDER BY employee_id, valid_from;
SELECT * FROM employee_history ORDER BY history_id;
-- Question: how many Carol rows are in history, and what did each one claim?

-- -----------------------------------------------------
-- 3d. Two kinds of "delete"
-- -----------------------------------------------------
-- (1) It stopped being true: Bob leaves on 2025-09-30.
--     This is a VALID-time end: the row stays current, its period is closed.
UPDATE employee
SET valid_to = DATE '2025-09-30'
WHERE employee_name='Bob'
  AND valid_to = DATE 'infinity';

-- (2) It was never true: Dave was entered by mistake.
--     This is a TRANSACTION-time end: the row is deleted, and the audit
--     trigger keeps it in history with the moment the mistake was retracted.
INSERT INTO employee(employee_name,salary,valid_from)
VALUES ('Dave',3900,DATE '2025-06-01');

INSERT INTO demo_marks VALUES ('dave_entered', clock_timestamp());

DELETE FROM employee
WHERE employee_name='Dave';

INSERT INTO demo_marks VALUES ('dave_retracted', clock_timestamp());

SELECT * FROM employee ORDER BY employee_id, valid_from;
SELECT * FROM employee_history ORDER BY history_id;
-- Question: Bob and Dave are both "gone". In which table, and in which clock,
-- does each of them still exist?

-- =====================================================
-- PART 4 - BITEMPORAL QUERIES
-- =====================================================
-- One view over current and historical rows. Current rows are believed
-- "until further notice", so their transaction_end is 'infinity'.
CREATE VIEW employee_bitemporal AS
SELECT employee_id,
       employee_name,
       salary,
       valid_from,
       valid_to,
       transaction_start,
       TIMESTAMP 'infinity' AS transaction_end,
       'CURRENT' AS source
FROM employee
UNION ALL
SELECT employee_id,
       employee_name,
       salary,
       valid_from,
       valid_to,
       transaction_start,
       transaction_end,
       'HISTORY'
FROM employee_history;

-- Combined timeline: every belief the database ever held
SELECT *
FROM employee_bitemporal
ORDER BY employee_id, transaction_start, valid_from;

-- The one predicate behind every question below:
--   valid at V     :  valid_from <= V  AND  V < valid_to
--   known at T     :  transaction_start <= T  AND  T < transaction_end

-- 4.1 Current state: valid today, as known now
SELECT employee_name, salary, valid_from, valid_to
FROM employee_bitemporal
WHERE valid_from <= CURRENT_DATE AND CURRENT_DATE < valid_to
  AND transaction_end = TIMESTAMP 'infinity'
ORDER BY employee_name;
-- Expected: Alice 7000, Carol 4800. Bob left in 2025; Dave never existed.

-- 4.2 Rollback: what did the database believe right after Alice's 6500 update?
SELECT employee_name, salary, valid_from, valid_to, transaction_start, transaction_end
FROM employee_bitemporal
WHERE transaction_start <= (SELECT marked_at FROM demo_marks WHERE label='alice_6500')
  AND (SELECT marked_at FROM demo_marks WHERE label='alice_6500') < transaction_end
ORDER BY employee_name;
-- Expected: Alice 6500, Bob 4200 (no Carol yet, no raise yet).

-- 4.3 Valid time: what salary was actually valid on 2025-05-15, as known now?
SELECT employee_name, salary, valid_from, valid_to
FROM employee_bitemporal
WHERE valid_from <= DATE '2025-05-15' AND DATE '2025-05-15' < valid_to
  AND transaction_end = TIMESTAMP 'infinity'
ORDER BY employee_name;
-- Expected: Alice 7000, Bob 4200 (still employed then), Carol 4800.

-- 4.4 Bitemporal: Carol's salary valid on 2025-03-15, as known at three moments.
-- The same question, three correct answers.
SELECT m.label AS known_at,
       b.salary,
       b.valid_from,
       b.valid_to
FROM demo_marks m
JOIN employee_bitemporal b
  ON b.transaction_start <= m.marked_at AND m.marked_at < b.transaction_end
WHERE m.label IN ('carol_hired','carol_4800','carol_date_fixed')
  AND b.employee_name = 'Carol'
  AND b.valid_from <= DATE '2025-03-15' AND DATE '2025-03-15' < b.valid_to
ORDER BY m.marked_at;
-- Expected: carol_hired -> 4500, carol_4800 -> 4800, carol_date_fixed -> 4500.

-- 4.5 Sequenced history: Alice's salary over time, as known now
SELECT salary, valid_from, valid_to
FROM employee_bitemporal
WHERE employee_name='Alice'
  AND transaction_end = TIMESTAMP 'infinity'
ORDER BY valid_from;
-- Expected: 6500 [2025-01-01, 2025-05-01), 7000 [2025-05-01, infinity).

-- 4.6 The retracted row: Dave as known between the two marks
SELECT employee_name, salary, source, transaction_start, transaction_end
FROM employee_bitemporal
WHERE transaction_start <= (SELECT marked_at FROM demo_marks WHERE label='dave_entered')
  AND (SELECT marked_at FROM demo_marks WHERE label='dave_entered') < transaction_end
  AND employee_name='Dave';
-- Expected: one HISTORY row. Run the same query with 'dave_retracted': no row.

-- Discussion:
-- 1. What is Alice's salary today? (4.1)
-- 2. What did the database believe Alice's salary was after mark alice_6500? (4.2)
-- 3. What salary was actually valid on 2025-05-15? (4.3)
-- 4. On 2025-03-15, what did the database believe was valid, at each of the
--    three moments? Why are all three answers correct? (4.4)
-- 5. Which invariant did the overlap trigger protect in 3c, and why could a
--    plain UPDATE of valid_from (the first version of this demo) never
--    produce the Jan-Mar row for Carol?
