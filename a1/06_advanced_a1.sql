-- 06_advanced_a1.sql: A1, the db handles transaction time itself
-- procedures do all writes (close old row + insert new one),
-- triggers block everything else. run once, after 01-05.

USE football_bt;
SET time_zone = '+00:00';

DROP PROCEDURE IF EXISTS sp_open_tx;
DROP PROCEDURE IF EXISTS sp_assert_fact;
DROP PROCEDURE IF EXISTS sp_end_fact;
DROP PROCEDURE IF EXISTS sp_correct_fact;
DROP PROCEDURE IF EXISTS sp_retract_fact;
DROP PROCEDURE IF EXISTS sp_try;

DELIMITER //

-- ---------- write API ----------

-- logs a change in tx_registry, returns tx_id and time
CREATE PROCEDURE sp_open_tx(
    IN p_author VARCHAR(100),
    IN p_reason VARCHAR(500),
    OUT p_tx_id BIGINT,
    OUT p_now DATETIME(6))
BEGIN
    -- @sim_now if set, else real time
    SET p_now = COALESCE(CAST(@sim_now AS DATETIME(6)), CURRENT_TIMESTAMP(6));

    -- tx time can't go backwards
    IF p_now <= (SELECT COALESCE(MAX(tx_time), '1000-01-01') FROM tx_registry) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Clock must move forward: @sim_now is not after the last change';
    END IF;

    INSERT INTO tx_registry (tx_time, author, reason) VALUES (p_now, p_author, p_reason);
    SET p_tx_id = LAST_INSERT_ID();
END//


-- set a contract for [from, to), to = NULL means open
-- overlapping rows get closed, their parts outside the period are kept
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

    -- on error: rollback, clear the flag, rethrow
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

    -- close overlapping rows
    UPDATE contract_version
    SET tx_to = v_now
    WHERE player_id = p_player_id
      AND club_id = p_club_id
      AND tx_to = v_open
      AND valid_from < v_to
      AND p_valid_from < valid_to;

    -- keep the part before the new period
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

    -- keep the part after it
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

    -- the new row
    INSERT INTO contract_version
    (player_id, club_id, contract_type, salary_eur, valid_from, valid_to, tx_from, tx_id)
    VALUES (p_player_id, p_club_id, p_type, p_salary, p_valid_from, v_to, v_now, v_tx_id);

    SET @via_api = NULL;
    COMMIT;
END//


-- contract really ended on p_end_date (E5)
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

    -- current row that covers the end date
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


-- fix a wrong row (E4), NULL = keep the old value
-- refuses if the fixed row would overlap another one
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

    -- new values
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


-- row was never true (E8): close it, no new row
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


-- ---------- guard triggers ----------
-- same 3 on every history table: insert only via the API, only tx_to
-- can change (open rows, via the API), never delete.
-- a trigger can't write to its own table (error 1442), so they only guard.

-- contract_version
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

-- club_version
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

-- head_coach_version
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


-- helper for the negative tests: runs a statement, shows the error, rolls back
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


-- ---------- demo, all through the API ----------
-- valid dates start 1 jul 2026, so the 05 results don't change

-- A1-1 Hansen signs for EAS from 1 jul (E2)
SET @sim_now = '2026-06-05 10:00:00';
CALL sp_assert_fact(69, 4, 'PERMANENT', 260000.00, '2026-07-01', NULL,
                    'clerk_ana', 'A1-1 | E2: Hansen signs for EAS from 1 Jul');

-- A1-2 Walsh raise at NOR from 1 jul, splits his row (E2)
SET @sim_now = '2026-06-10 10:00:00';
CALL sp_assert_fact(1, 1, 'PERMANENT', 1000000.00, '2026-07-01', NULL,
                    'clerk_ana', 'A1-2 | E2: Walsh raise at NOR from 1 Jul');

-- A1-3 Hansen salary typo, really 290k (E4)
SET @sim_now = '2026-06-12 09:00:00';
SET @v = (SELECT version_id
          FROM contract_version
          WHERE player_id = 69
            AND club_id = 4
            AND tx_to = '9999-12-31 23:59:59.999999');
CALL sp_correct_fact(@v, NULL, 290000.00, NULL, NULL,
                     'clerk_ana', 'A1-3 | E4 correction: Hansen salary 260,000 -> 290,000');

-- A1-4 Lopes leaves SOU after 31 aug (E5)
SET @sim_now = '2026-06-15 11:00:00';
CALL sp_end_fact(66, 6, '2026-09-01',
                 'clerk_ana', 'A1-4 | E5 end: Lopes leaves SOU after 31 Aug');

-- A1-5 Lindqvist signed for WES by mistake
SET @sim_now = '2026-06-20 08:00:00';
CALL sp_assert_fact(70, 5, 'PERMANENT', 200000.00, '2026-07-01', NULL,
                    'clerk_bob', 'A1-5 | Lindqvist signs for WES (entered by mistake)');

-- A1-6 retract it (E8)
SET @sim_now = '2026-06-20 15:00:00';
SET @v = (SELECT version_id
          FROM contract_version
          WHERE player_id = 70
            AND club_id = 5
            AND tx_to = '9999-12-31 23:59:59.999999');
CALL sp_retract_fact(@v, 'clerk_ana', 'A1-6 | E8 retraction: Lindqvist was never signed');

-- A1-7 real clock (@sim_now cleared): Hansen contract ends 31 dec (E5)
SET @sim_now = NULL;
CALL sp_end_fact(69, 4, '2027-01-01',
                 'clerk_ana', 'A1-7 | E5 end: Hansen contract ends 31 Dec (real clock)');


-- ---------- check the demo ----------

-- A1 changes in tx_registry: 7 rows, last one with real time
SELECT *
FROM tx_registry
WHERE reason LIKE 'A1-%'
ORDER BY tx_id;

-- Hansen: 260k (closed), 290k (closed), 290k until 2027-01-01
SELECT *
FROM contract_version
WHERE player_id = 69
ORDER BY version_id;

-- Walsh: 950k until 1 jul 2026, 1M after
SELECT *
FROM contract_version
WHERE player_id = 1
ORDER BY version_id;

-- Q3 on the demo: 5x E2, A1-3 E4, A1-6 E8
SELECT story_event, subject, change_date, delay_days, classification
FROM v_q3_late_proactive_corrections
WHERE story_event LIKE 'A1-%'
ORDER BY recorded_at;

-- Q0 still 0
SELECT *
FROM v_integrity_violations;


-- ---------- negative tests, all should say blocked ----------

-- direct writes (triggers)
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

-- API misuse (procedures)
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

-- Q0 after the tests: still 0
SELECT *
FROM v_integrity_violations;