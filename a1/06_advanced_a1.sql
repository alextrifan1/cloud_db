-- 06_advanced_a1.sql
--
-- 1. Write API (stored procedures) for contracts. Each call is one change:
--    it logs itself in tx_registry, closes the old belief and writes the
--    new one. The time comes from @sim_now if set, else CURRENT_TIMESTAMP(6).
-- 2. Guard triggers on all three history tables. They only block:
--    direct inserts, direct closes, changes to business columns,
--    changes to closed rows, and any DELETE.
--    The procedures set @via_api = 1 while they write; the triggers
--    allow writes only when it is set.
-- 3. Demo: six more changes, all made through the API.
-- 4. Negative tests: every forbidden operation, with the error it gets.

USE football_bt;
SET time_zone = '+00:00';

DROP PROCEDURE IF EXISTS sp_open_tx;
DROP PROCEDURE IF EXISTS sp_assert_fact;
DROP PROCEDURE IF EXISTS sp_end_fact;
DROP PROCEDURE IF EXISTS sp_correct_fact;
DROP PROCEDURE IF EXISTS sp_retract_fact;
DROP PROCEDURE IF EXISTS sp_try;

DELIMITER //

-- =====================================================================
-- Part 1. Write API
-- =====================================================================

-- Logs one change in tx_registry and returns its id and time.
-- Used by every procedure below.
CREATE PROCEDURE sp_open_tx(
    IN p_author VARCHAR(100),
    IN p_reason VARCHAR(500),
    OUT p_tx_id BIGINT,
    OUT p_now DATETIME(6))
BEGIN
    -- Simulated clock if set, real clock otherwise.
    SET p_now = COALESCE(CAST(@sim_now AS DATETIME(6)), CURRENT_TIMESTAMP(6));

    -- Transaction time only moves forward.
    IF p_now <= (SELECT COALESCE(MAX(tx_time), '1000-01-01') FROM tx_registry) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Clock must move forward: @sim_now is not after the last change';
    END IF;

    INSERT INTO tx_registry (tx_time, author, reason) VALUES (p_now, p_author, p_reason);
    SET p_tx_id = LAST_INSERT_ID();
END//


-- "From p_valid_from to p_valid_to, this is the contract."
-- Covers a new contract and a change from a date (raise, new type).
-- Rows of the same player and club that overlap the period are closed;
-- their parts before and after the period are written again unchanged.
-- p_valid_to = NULL means open-ended.
CREATE PROCEDURE sp_assert_fact(
    IN p_player_id INT,
    IN p_club_id INT,
    IN p_type VARCHAR(10),
    IN p_salary DECIMAL(12, 2),
    IN p_valid_from DATE,
    IN p_valid_to DATE,
    IN p_author VARCHAR(100),
    IN p_reason VARCHAR(500))
BEGIN
    DECLARE v_open DATETIME(6) DEFAULT '9999-12-31 23:59:59.999999';
    DECLARE v_to DATE DEFAULT COALESCE(p_valid_to, '9999-12-31');
    DECLARE v_tx_id BIGINT;
    DECLARE v_now DATETIME(6);

    -- On any error: undo everything, clear the flag, pass the error on.
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
        BEGIN
            SET @via_api = NULL;
            ROLLBACK;
            RESIGNAL;
        END;

    IF p_valid_from >= v_to THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'sp_assert_fact: valid_from must be before valid_to';
    END IF;

    START TRANSACTION;
    CALL sp_open_tx(p_author, p_reason, v_tx_id, v_now);
    SET @via_api = 1;

    -- 1. Close current rows that overlap the new period.
    UPDATE contract_version
    SET tx_to = v_now
    WHERE player_id = p_player_id
      AND club_id = p_club_id
      AND tx_to = v_open
      AND valid_from < v_to
      AND p_valid_from < valid_to;

    -- 2. Keep the part of each closed row before the new period.
    INSERT INTO contract_version
    (player_id, club_id, contract_type, salary_eur, valid_from, valid_to, tx_from, tx_id)
    SELECT player_id,
           club_id,
           contract_type,
           salary_eur,
           valid_from,
           p_valid_from,
           v_now,
           v_tx_id
    FROM contract_version
    WHERE player_id = p_player_id
      AND club_id = p_club_id
      AND tx_to = v_now
      AND valid_from < p_valid_from;

    -- 3. Keep the part of each closed row after the new period.
    INSERT INTO contract_version
    (player_id, club_id, contract_type, salary_eur, valid_from, valid_to, tx_from, tx_id)
    SELECT player_id,
           club_id,
           contract_type,
           salary_eur,
           v_to,
           valid_to,
           v_now,
           v_tx_id
    FROM contract_version
    WHERE player_id = p_player_id
      AND club_id = p_club_id
      AND tx_to = v_now
      AND valid_to > v_to;

    -- 4. The new fact.
    INSERT INTO contract_version
    (player_id, club_id, contract_type, salary_eur, valid_from, valid_to, tx_from, tx_id)
    VALUES (p_player_id, p_club_id, p_type, p_salary, p_valid_from, v_to, v_now, v_tx_id);

    SET @via_api = NULL;
    COMMIT;
END//


-- "The contract really ended on p_end_date" (E5).
-- Closes the running row and writes it again with that end date.
CREATE PROCEDURE sp_end_fact(
    IN p_player_id INT,
    IN p_club_id INT,
    IN p_end_date DATE,
    IN p_author VARCHAR(100),
    IN p_reason VARCHAR(500))
BEGIN
    DECLARE v_open DATETIME(6) DEFAULT '9999-12-31 23:59:59.999999';
    DECLARE v_tx_id BIGINT;
    DECLARE v_now DATETIME(6);
    DECLARE v_version BIGINT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
        BEGIN
            SET @via_api = NULL;
            ROLLBACK;
            RESIGNAL;
        END;

    -- The current row that runs across the end date.
    SELECT MAX(version_id)
    INTO v_version
    FROM contract_version
    WHERE player_id = p_player_id
      AND club_id = p_club_id
      AND tx_to = v_open
      AND valid_from < p_end_date
      AND p_end_date < valid_to;

    IF v_version IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'sp_end_fact: no running contract across that date';
    END IF;

    START TRANSACTION;
    CALL sp_open_tx(p_author, p_reason, v_tx_id, v_now);
    SET @via_api = 1;

    UPDATE contract_version SET tx_to = v_now WHERE version_id = v_version;

    INSERT INTO contract_version
    (player_id, club_id, contract_type, salary_eur, valid_from, valid_to, tx_from, tx_id)
    SELECT player_id,
           club_id,
           contract_type,
           salary_eur,
           valid_from,
           p_end_date,
           v_now,
           v_tx_id
    FROM contract_version
    WHERE version_id = v_version;

    SET @via_api = NULL;
    COMMIT;
END//


-- "This row was wrong" (E4): new values and/or dates for one current row.
-- NULL keeps the old value. The corrected row must not overlap another
-- current row of the same player and club.
CREATE PROCEDURE sp_correct_fact(
    IN p_version_id BIGINT,
    IN p_type VARCHAR(10),
    IN p_salary DECIMAL(12, 2),
    IN p_valid_from DATE,
    IN p_valid_to DATE,
    IN p_author VARCHAR(100),
    IN p_reason VARCHAR(500))
BEGIN
    DECLARE v_open DATETIME(6) DEFAULT '9999-12-31 23:59:59.999999';
    DECLARE v_tx_id BIGINT;
    DECLARE v_now DATETIME(6);
    DECLARE v_player INT;
    DECLARE v_club INT;
    DECLARE v_type VARCHAR(10);
    DECLARE v_salary DECIMAL(12, 2);
    DECLARE v_from DATE;
    DECLARE v_to DATE;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
        BEGIN
            SET @via_api = NULL;
            ROLLBACK;
            RESIGNAL;
        END;

    SELECT player_id, club_id, contract_type, salary_eur, valid_from, valid_to
    INTO v_player, v_club, v_type, v_salary, v_from, v_to
    FROM contract_version
    WHERE version_id = p_version_id
      AND tx_to = v_open;

    IF v_player IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'sp_correct_fact: row not found or already closed';
    END IF;

    -- New values; NULL means "keep".
    SET v_type = COALESCE(p_type, v_type);
    SET v_salary = COALESCE(p_salary, v_salary);
    SET v_from = COALESCE(p_valid_from, v_from);
    SET v_to = COALESCE(p_valid_to, v_to);

    IF v_from >= v_to THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'sp_correct_fact: valid_from must be before valid_to';
    END IF;

    IF EXISTS (SELECT 1
               FROM contract_version
               WHERE player_id = v_player
                 AND club_id = v_club
                 AND tx_to = v_open
                 AND version_id <> p_version_id
                 AND valid_from < v_to
                 AND v_from < valid_to) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'sp_correct_fact: corrected period overlaps another contract';
    END IF;

    START TRANSACTION;
    CALL sp_open_tx(p_author, p_reason, v_tx_id, v_now);
    SET @via_api = 1;

    UPDATE contract_version SET tx_to = v_now WHERE version_id = p_version_id;

    INSERT INTO contract_version
    (player_id, club_id, contract_type, salary_eur, valid_from, valid_to, tx_from, tx_id)
    VALUES (v_player, v_club, v_type, v_salary, v_from, v_to, v_now, v_tx_id);

    SET @via_api = NULL;
    COMMIT;
END//


-- "This row was never true" (E8): close it, write nothing new.
CREATE PROCEDURE sp_retract_fact(
    IN p_version_id BIGINT,
    IN p_author VARCHAR(100),
    IN p_reason VARCHAR(500))
BEGIN
    DECLARE v_open DATETIME(6) DEFAULT '9999-12-31 23:59:59.999999';
    DECLARE v_tx_id BIGINT;
    DECLARE v_now DATETIME(6);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
        BEGIN
            SET @via_api = NULL;
            ROLLBACK;
            RESIGNAL;
        END;

    IF NOT EXISTS (SELECT 1
                   FROM contract_version
                   WHERE version_id = p_version_id
                     AND tx_to = v_open) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'sp_retract_fact: row not found or already closed';
    END IF;

    START TRANSACTION;
    CALL sp_open_tx(p_author, p_reason, v_tx_id, v_now);
    SET @via_api = 1;

    UPDATE contract_version SET tx_to = v_now WHERE version_id = p_version_id;

    SET @via_api = NULL;
    COMMIT;
END//


-- =====================================================================
-- Part 2. Guard triggers, the same three on each history table:
--   BEFORE INSERT  only through the API
--   BEFORE UPDATE  closed rows never change; only tx_to may change,
--                  and only through the API
--   BEFORE DELETE  never
-- A trigger cannot write to its own table (error 1442), so the
-- close + insert logic lives in the procedures; triggers only guard.
-- =====================================================================

-- contract_version ------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_contract_bi
    BEFORE INSERT
    ON contract_version
    FOR EACH ROW
BEGIN
    IF @via_api IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'contract_version: insert only through the write API (sp_*)';
    END IF;
END//

CREATE OR REPLACE TRIGGER trg_contract_bu
    BEFORE UPDATE
    ON contract_version
    FOR EACH ROW
BEGIN
    IF OLD.tx_to <> '9999-12-31 23:59:59.999999' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'contract_version: closed rows are history and cannot change';
    END IF;
    IF NOT (NEW.version_id <=> OLD.version_id
        AND NEW.player_id <=> OLD.player_id
        AND NEW.club_id <=> OLD.club_id
        AND NEW.contract_type <=> OLD.contract_type
        AND NEW.salary_eur <=> OLD.salary_eur
        AND NEW.valid_from <=> OLD.valid_from
        AND NEW.valid_to <=> OLD.valid_to
        AND NEW.tx_from <=> OLD.tx_from
        AND NEW.tx_id <=> OLD.tx_id) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'contract_version: only tx_to may change';
    END IF;
    IF @via_api IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'contract_version: close rows only through the write API (sp_*)';
    END IF;
END//

CREATE OR REPLACE TRIGGER trg_contract_bd
    BEFORE DELETE
    ON contract_version
    FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT =
            'contract_version: rows are never deleted (use sp_end_fact or sp_retract_fact)';
END//

-- club_version ----------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_club_bi
    BEFORE INSERT
    ON club_version
    FOR EACH ROW
BEGIN
    IF @via_api IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'club_version: insert only through the write API (sp_*)';
    END IF;
END//

CREATE OR REPLACE TRIGGER trg_club_bu
    BEFORE UPDATE
    ON club_version
    FOR EACH ROW
BEGIN
    IF OLD.tx_to <> '9999-12-31 23:59:59.999999' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'club_version: closed rows are history and cannot change';
    END IF;
    IF NOT (NEW.version_id <=> OLD.version_id
        AND NEW.club_id <=> OLD.club_id
        AND NEW.name <=> OLD.name
        AND NEW.budget_eur <=> OLD.budget_eur
        AND NEW.valid_from <=> OLD.valid_from
        AND NEW.valid_to <=> OLD.valid_to
        AND NEW.tx_from <=> OLD.tx_from
        AND NEW.tx_id <=> OLD.tx_id) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'club_version: only tx_to may change';
    END IF;
    IF @via_api IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'club_version: close rows only through the write API (sp_*)';
    END IF;
END//

CREATE OR REPLACE TRIGGER trg_club_bd
    BEFORE DELETE
    ON club_version
    FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'club_version: rows are never deleted';
END//

-- head_coach_version ----------------------------------------------------
CREATE OR REPLACE TRIGGER trg_coach_bi
    BEFORE INSERT
    ON head_coach_version
    FOR EACH ROW
BEGIN
    IF @via_api IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'head_coach_version: insert only through the write API (sp_*)';
    END IF;
END//

CREATE OR REPLACE TRIGGER trg_coach_bu
    BEFORE UPDATE
    ON head_coach_version
    FOR EACH ROW
BEGIN
    IF OLD.tx_to <> '9999-12-31 23:59:59.999999' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'head_coach_version: closed rows are history and cannot change';
    END IF;
    IF NOT (NEW.version_id <=> OLD.version_id
        AND NEW.club_id <=> OLD.club_id
        AND NEW.coach_id <=> OLD.coach_id
        AND NEW.valid_from <=> OLD.valid_from
        AND NEW.valid_to <=> OLD.valid_to
        AND NEW.tx_from <=> OLD.tx_from
        AND NEW.tx_id <=> OLD.tx_id) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'head_coach_version: only tx_to may change';
    END IF;
    IF @via_api IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'head_coach_version: close rows only through the write API (sp_*)';
    END IF;
END//

CREATE OR REPLACE TRIGGER trg_coach_bd
    BEFORE DELETE
    ON head_coach_version
    FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'head_coach_version: rows are never deleted';
END//


-- =====================================================================
-- Helper for the negative tests: runs one statement, catches the error
-- and shows it, so the script keeps going. Everything it does is rolled
-- back, in case something is not blocked.
-- =====================================================================
CREATE PROCEDURE sp_try(IN p_attempt VARCHAR(200), IN p_sql TEXT)
BEGIN
    DECLARE v_msg TEXT DEFAULT NULL;
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
        GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;

    SET @via_api = NULL;
    SET @try_sql = p_sql;
    START TRANSACTION;
    PREPARE stmt FROM @try_sql;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;
    ROLLBACK;

    SELECT p_attempt                                   AS attempt,
           IF(v_msg IS NULL, 'NOT BLOCKED', 'blocked') AS result,
           v_msg                                       AS error_message;
END//

DELIMITER ;


-- =====================================================================
-- Part 3. Demo: six changes made only through the API.
-- All valid dates are from 1 Jul 2026 on, after the season used by
-- the Part C tests, so those results stay the same.
-- =====================================================================

-- A1-1 | E2: free agent Hansen (69) signs for EAS (4) from 1 Jul 2026.
SET @sim_now = '2026-06-05 10:00:00';
CALL sp_assert_fact(69, 4, 'PERMANENT', 260000.00, '2026-07-01', NULL,
                    'clerk_ana', 'A1-1 | E2: Hansen signs for EAS from 1 Jul');

-- A1-2 | E2: Walsh (1) gets a raise at NOR (1) from 1 Jul 2026.
-- His open row (950,000 from 1 Jan) is split at 1 Jul.
SET @sim_now = '2026-06-10 10:00:00';
CALL sp_assert_fact(1, 1, 'PERMANENT', 1000000.00, '2026-07-01', NULL,
                    'clerk_ana', 'A1-2 | E2: Walsh raise at NOR from 1 Jul');

-- A1-3 | E4: Hansen's salary was typed wrong; it is 290,000.
SET @sim_now = '2026-06-12 09:00:00';
SET @v = (SELECT version_id
          FROM contract_version
          WHERE player_id = 69
            AND club_id = 4
            AND tx_to = '9999-12-31 23:59:59.999999');
CALL sp_correct_fact(@v, NULL, 290000.00, NULL, NULL,
                     'clerk_ana', 'A1-3 | E4 correction: Hansen salary 260,000 -> 290,000');

-- A1-4 | E5: Lopes (66) leaves SOU (6); last day 31 Aug 2026.
SET @sim_now = '2026-06-15 11:00:00';
CALL sp_end_fact(66, 6, '2026-09-01',
                 'clerk_ana', 'A1-4 | E5 end: Lopes leaves SOU after 31 Aug');

-- A1-5: a clerk wrongly signs Lindqvist (70) for WES (5).
SET @sim_now = '2026-06-20 08:00:00';
CALL sp_assert_fact(70, 5, 'PERMANENT', 200000.00, '2026-07-01', NULL,
                    'clerk_bob', 'A1-5 | Lindqvist signs for WES (entered by mistake)');

-- A1-6 | E8: that contract never existed.
SET @sim_now = '2026-06-20 15:00:00';
SET @v = (SELECT version_id
          FROM contract_version
          WHERE player_id = 70
            AND club_id = 5
            AND tx_to = '9999-12-31 23:59:59.999999');
CALL sp_retract_fact(@v, 'clerk_ana', 'A1-6 | E8 retraction: Lindqvist was never signed');

-- A1-7 | E5, on the real clock: Hansen's contract will end on 31 Dec 2026.
-- @sim_now is cleared, so the API uses CURRENT_TIMESTAMP(6).
SET @sim_now = NULL;
CALL sp_end_fact(69, 4, '2027-01-01',
                 'clerk_ana', 'A1-7 | E5 end: Hansen contract ends 31 Dec (real clock)');


-- Check the demo -------------------------------------------------------

-- Expect 7 rows A1-1 .. A1-7; the last one has today's real time.
SELECT *
FROM tx_registry
WHERE reason LIKE 'A1-%'
ORDER BY tx_id;

-- Hansen: 260,000 (closed by A1-3), 290,000 (closed by A1-7),
-- 290,000 ending 2027-01-01 (current).
SELECT *
FROM contract_version
WHERE player_id = 69
ORDER BY version_id;

-- Walsh: his 950,000 row now ends 1 Jul 2026, 1,000,000 from then.
SELECT *
FROM contract_version
WHERE player_id = 1
ORDER BY version_id;

-- Q3 labels the API changes too. Expect:
--   A1-1, A1-2, A1-4, A1-5, A1-7 PROACTIVE (E2), A1-3 CORRECTION (E4),
--   A1-6 RETRACTION (E8)
SELECT story_event, subject, change_date, delay_days, classification
FROM v_q3_late_proactive_corrections
WHERE story_event LIKE 'A1-%'
ORDER BY recorded_at;

-- Expect 0 rows: the data is still consistent.
SELECT *
FROM v_integrity_violations;


-- =====================================================================
-- Part 4. Negative tests. Each line tries a forbidden operation.
-- Expect result = 'blocked' and the trigger or procedure message.
-- =====================================================================

-- Direct writes (triggers)
CALL sp_try('N1 contract: change a business column',
            'UPDATE contract_version SET salary_eur = 1 WHERE player_id = 2 AND tx_to = ''9999-12-31 23:59:59.999999''');

CALL sp_try('N2 contract: change a closed row',
            'UPDATE contract_version SET tx_to = ''2026-01-01'' WHERE tx_to < ''9999-12-31'' LIMIT 1');

CALL sp_try('N3 contract: close a row without the API',
            'UPDATE contract_version SET tx_to = NOW(6) WHERE player_id = 2 AND tx_to = ''9999-12-31 23:59:59.999999''');

CALL sp_try('N4 contract: insert without the API',
            'INSERT INTO contract_version (player_id, club_id, contract_type, salary_eur, valid_from, tx_from, tx_id) VALUES (68, 1, ''PERMANENT'', 1000, ''2026-07-01'', NOW(6), 1)');

CALL sp_try('N5 contract: physical delete',
            'DELETE FROM contract_version WHERE player_id = 2 LIMIT 1');

CALL sp_try('N6 head coach: change the holder in place',
            'UPDATE head_coach_version SET coach_id = 7 WHERE club_id = 1 AND tx_to = ''9999-12-31 23:59:59.999999''');

CALL sp_try('N7 head coach: physical delete',
            'DELETE FROM head_coach_version WHERE club_id = 1 LIMIT 1');

CALL sp_try('N8 club: change the budget in place',
            'UPDATE club_version SET budget_eur = 1 WHERE club_id = 1 AND tx_to = ''9999-12-31 23:59:59.999999''');

CALL sp_try('N9 club: physical delete',
            'DELETE FROM club_version WHERE club_id = 1 LIMIT 1');

-- Misuse of the API (procedures)
SET @sim_now = '2025-01-01 00:00:00';
CALL sp_try('N10 API: clock moving backwards',
            'CALL sp_assert_fact(68, 1, ''PERMANENT'', 1000, ''2026-07-01'', NULL, ''test'', ''backwards'')');
SET @sim_now = NULL;

CALL sp_try('N11 API: retract a row that is already closed',
            'CALL sp_retract_fact((SELECT MIN(version_id) FROM contract_version WHERE tx_to < ''9999-12-31''), ''test'', ''closed'')');

CALL sp_try('N12 API: correction that overlaps another contract',
            'CALL sp_correct_fact((SELECT MAX(version_id) FROM contract_version WHERE player_id = 57 AND tx_to = ''9999-12-31 23:59:59.999999''), NULL, NULL, ''2025-08-01'', NULL, ''test'', ''overlap'')');

CALL sp_try('N13 API: end date with no running contract',
            'CALL sp_end_fact(68, 1, ''2026-08-01'', ''test'', ''no contract'')');

-- Nothing above changed the data. Expect 0 rows.
SELECT *
FROM v_integrity_violations;