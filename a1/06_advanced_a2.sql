-- 06_advanced_a2.sql: A2, Q1/Q5/Q6 with MariaDB's own temporal features
-- valid time: PERIOD FOR + WITHOUT OVERLAPS, tx time: SYSTEM VERSIONING
-- every result is compared with the core views. run after 01-05 (A1 optional).

USE football_bt;
SET time_zone = '+00:00';

DROP TABLE IF EXISTS contract_native;
DROP TABLE IF EXISTS head_coach_native;
DROP PROCEDURE IF EXISTS sp_a2_compare;
DROP PROCEDURE IF EXISTS sp_a2_try;


-- ---------- native tables ----------

-- key WITHOUT OVERLAPS = I1 checked by the engine (no tx_id here)
CREATE TABLE contract_native (
                                 player_id      INT            NOT NULL,
                                 club_id        INT            NOT NULL,
                                 contract_type  ENUM('PERMANENT', 'LOAN') NOT NULL,
                                 salary_eur     DECIMAL(12,2)  NOT NULL,
                                 valid_from     DATE           NOT NULL,
                                 valid_to       DATE           NOT NULL,
                                 row_start      TIMESTAMP(6)   GENERATED ALWAYS AS ROW START,
                                 row_end        TIMESTAMP(6)   GENERATED ALWAYS AS ROW END,
                                 PERIOD FOR valid_period (valid_from, valid_to),
                                 PERIOD FOR SYSTEM_TIME (row_start, row_end),
                                 PRIMARY KEY (player_id, club_id, valid_period WITHOUT OVERLAPS),
                                 FOREIGN KEY (player_id) REFERENCES player (player_id),
                                 FOREIGN KEY (club_id)   REFERENCES club (club_id)
) WITH SYSTEM VERSIONING;

-- key WITHOUT OVERLAPS = I3, one coach per club at a time
CREATE TABLE head_coach_native (
                                   club_id     INT           NOT NULL,
                                   coach_id    INT           NOT NULL,
                                   valid_from  DATE          NOT NULL,
                                   valid_to    DATE          NOT NULL,
                                   row_start   TIMESTAMP(6)  GENERATED ALWAYS AS ROW START,
                                   row_end     TIMESTAMP(6)  GENERATED ALWAYS AS ROW END,
                                   PERIOD FOR valid_period (valid_from, valid_to),
                                   PERIOD FOR SYSTEM_TIME (row_start, row_end),
                                   PRIMARY KEY (club_id, valid_period WITHOUT OVERLAPS),
                                   FOREIGN KEY (club_id)  REFERENCES club (club_id),
                                   FOREIGN KEY (coach_id) REFERENCES coach (coach_id)
) WITH SYSTEM VERSIONING;


-- ---------- load the history ----------
-- normally MariaDB stamps tx time with the real clock; insert_history
-- lets us copy tx_from/tx_to into row_start/row_end instead.
-- closed rows get both, current rows only row_start.
SET @@system_versioning_insert_history = ON;

INSERT INTO contract_native
(player_id, club_id, contract_type, salary_eur, valid_from, valid_to, row_start, row_end)
SELECT player_id, club_id, contract_type, salary_eur, valid_from, valid_to, tx_from, tx_to
FROM   contract_version
WHERE  tx_to < '9999-12-31 23:59:59.999999';

INSERT INTO contract_native
(player_id, club_id, contract_type, salary_eur, valid_from, valid_to, row_start)
SELECT player_id, club_id, contract_type, salary_eur, valid_from, valid_to, tx_from
FROM   contract_version
WHERE  tx_to = '9999-12-31 23:59:59.999999';

INSERT INTO head_coach_native
(club_id, coach_id, valid_from, valid_to, row_start, row_end)
SELECT club_id, coach_id, valid_from, valid_to, tx_from, tx_to
FROM   head_coach_version
WHERE  tx_to < '9999-12-31 23:59:59.999999';

INSERT INTO head_coach_native
(club_id, coach_id, valid_from, valid_to, row_start)
SELECT club_id, coach_id, valid_from, valid_to, tx_from
FROM   head_coach_version
WHERE  tx_to = '9999-12-31 23:59:59.999999';

-- back to normal
SET @@system_versioning_insert_history = OFF;

-- row counts, native vs core (all and current)
SELECT 'contracts'   AS rows_of,
       (SELECT COUNT(*) FROM contract_version)                                           AS core_all,
       (SELECT COUNT(*) FROM contract_native FOR SYSTEM_TIME ALL)                        AS native_all,
       (SELECT COUNT(*) FROM contract_version WHERE tx_to = '9999-12-31 23:59:59.999999') AS core_current,
       (SELECT COUNT(*) FROM contract_native)                                            AS native_current
UNION ALL
SELECT 'head coaches',
       (SELECT COUNT(*) FROM head_coach_version),
       (SELECT COUNT(*) FROM head_coach_native FOR SYSTEM_TIME ALL),
       (SELECT COUNT(*) FROM head_coach_version WHERE tx_to = '9999-12-31 23:59:59.999999'),
       (SELECT COUNT(*) FROM head_coach_native);


-- ---------- compare helper ----------
-- each test fills a2_core (core view) and a2_native (native query),
-- then sp_a2_compare prints SAME or DIFFERENT
DROP TEMPORARY TABLE IF EXISTS a2_core;
DROP TEMPORARY TABLE IF EXISTS a2_native;
CREATE TEMPORARY TABLE a2_core (
                                   fact VARCHAR(20), person VARCHAR(101), club CHAR(3), details VARCHAR(40),
                                   valid_from DATE, valid_to DATE);
CREATE TEMPORARY TABLE a2_native LIKE a2_core;

DELIMITER //
CREATE PROCEDURE sp_a2_compare(IN p_test VARCHAR(100))
BEGIN
    SET @core_rows   = (SELECT COUNT(*) FROM a2_core);
    SET @native_rows = (SELECT COUNT(*) FROM a2_native);
    SET @only_core   = (SELECT COUNT(*) FROM (SELECT * FROM a2_core   EXCEPT SELECT * FROM a2_native) AS x);
    SET @only_native = (SELECT COUNT(*) FROM (SELECT * FROM a2_native EXCEPT SELECT * FROM a2_core)   AS y);

    SELECT p_test       AS test,
           @core_rows   AS core_rows,
           @native_rows AS native_rows,
           @only_core   AS only_in_core,
           @only_native AS only_in_native,
           IF(@core_rows = @native_rows AND @only_core = 0 AND @only_native = 0,
              'SAME', 'DIFFERENT') AS verdict;

    DELETE FROM a2_core   WHERE 1 = 1;
    DELETE FROM a2_native WHERE 1 = 1;
END//
DELIMITER ;


-- ---------- Q1 native ----------
-- tx time with FOR SYSTEM_TIME, valid time stays in the WHERE
-- (MariaDB has no AS OF for valid time in SELECT)
-- same players as in 05: Moreau, Hughes, Rossi, Ward

UPDATE query_params SET subject_id = 13 WHERE id = 1;
INSERT INTO a2_core
SELECT 'CONTRACT', CONCAT(first_name, ' ', last_name), club,
       CONCAT(contract_type, ' ', salary_eur), valid_from, valid_to
FROM v_q1_player_contracts_now;
INSERT INTO a2_native
SELECT 'CONTRACT', CONCAT(p.first_name, ' ', p.last_name), c.short_code,
       CONCAT(n.contract_type, ' ', n.salary_eur), n.valid_from, n.valid_to
FROM contract_native FOR SYSTEM_TIME AS OF CURRENT_TIMESTAMP(6) AS n
         JOIN player AS p ON p.player_id = n.player_id
         JOIN club   AS c ON c.club_id   = n.club_id
WHERE n.player_id = 13
  AND n.valid_from <= CURDATE() AND CURDATE() < n.valid_to;
CALL sp_a2_compare('Q1 Moreau (13)');

UPDATE query_params SET subject_id = 12 WHERE id = 1;
INSERT INTO a2_core
SELECT 'CONTRACT', CONCAT(first_name, ' ', last_name), club,
       CONCAT(contract_type, ' ', salary_eur), valid_from, valid_to
FROM v_q1_player_contracts_now;
INSERT INTO a2_native
SELECT 'CONTRACT', CONCAT(p.first_name, ' ', p.last_name), c.short_code,
       CONCAT(n.contract_type, ' ', n.salary_eur), n.valid_from, n.valid_to
FROM contract_native FOR SYSTEM_TIME AS OF CURRENT_TIMESTAMP(6) AS n
         JOIN player AS p ON p.player_id = n.player_id
         JOIN club   AS c ON c.club_id   = n.club_id
WHERE n.player_id = 12
  AND n.valid_from <= CURDATE() AND CURDATE() < n.valid_to;
CALL sp_a2_compare('Q1 Hughes (12)');

UPDATE query_params SET subject_id = 56 WHERE id = 1;
INSERT INTO a2_core
SELECT 'CONTRACT', CONCAT(first_name, ' ', last_name), club,
       CONCAT(contract_type, ' ', salary_eur), valid_from, valid_to
FROM v_q1_player_contracts_now;
INSERT INTO a2_native
SELECT 'CONTRACT', CONCAT(p.first_name, ' ', p.last_name), c.short_code,
       CONCAT(n.contract_type, ' ', n.salary_eur), n.valid_from, n.valid_to
FROM contract_native FOR SYSTEM_TIME AS OF CURRENT_TIMESTAMP(6) AS n
         JOIN player AS p ON p.player_id = n.player_id
         JOIN club   AS c ON c.club_id   = n.club_id
WHERE n.player_id = 56
  AND n.valid_from <= CURDATE() AND CURDATE() < n.valid_to;
CALL sp_a2_compare('Q1 Rossi (56), retracted loan hidden');

UPDATE query_params SET subject_id = 68 WHERE id = 1;
INSERT INTO a2_core
SELECT 'CONTRACT', CONCAT(first_name, ' ', last_name), club,
       CONCAT(contract_type, ' ', salary_eur), valid_from, valid_to
FROM v_q1_player_contracts_now;
INSERT INTO a2_native
SELECT 'CONTRACT', CONCAT(p.first_name, ' ', p.last_name), c.short_code,
       CONCAT(n.contract_type, ' ', n.salary_eur), n.valid_from, n.valid_to
FROM contract_native FOR SYSTEM_TIME AS OF CURRENT_TIMESTAMP(6) AS n
         JOIN player AS p ON p.player_id = n.player_id
         JOIN club   AS c ON c.club_id   = n.club_id
WHERE n.player_id = 68
  AND n.valid_from <= CURDATE() AND CURDATE() < n.valid_to;
CALL sp_a2_compare('Q1 Ward (68), no contract');


-- ---------- Q5 native (tx time only) ----------

-- go-live, 66 rows
UPDATE query_params SET known_at = '2025-07-01 12:00:00' WHERE id = 1;
SET @known_at = (SELECT known_at FROM query_params WHERE id = 1);
INSERT INTO a2_core
SELECT 'CONTRACT', CONCAT(first_name, ' ', last_name), club,
       CONCAT(contract_type, ' ', salary_eur), valid_from, valid_to
FROM v_q5_contracts_believed_at;
INSERT INTO a2_native
SELECT 'CONTRACT', CONCAT(p.first_name, ' ', p.last_name), c.short_code,
       CONCAT(n.contract_type, ' ', n.salary_eur), n.valid_from, n.valid_to
FROM contract_native FOR SYSTEM_TIME AS OF TIMESTAMP @known_at AS n
         JOIN player AS p ON p.player_id = n.player_id
         JOIN club   AS c ON c.club_id   = n.club_id;
CALL sp_a2_compare('Q5 at 2025-07-01 12:00');

-- 15 sep 12:00, wrong Rossi loan still believed, 70 rows
UPDATE query_params SET known_at = '2025-09-15 12:00:00' WHERE id = 1;
SET @known_at = (SELECT known_at FROM query_params WHERE id = 1);
INSERT INTO a2_core
SELECT 'CONTRACT', CONCAT(first_name, ' ', last_name), club,
       CONCAT(contract_type, ' ', salary_eur), valid_from, valid_to
FROM v_q5_contracts_believed_at;
INSERT INTO a2_native
SELECT 'CONTRACT', CONCAT(p.first_name, ' ', p.last_name), c.short_code,
       CONCAT(n.contract_type, ' ', n.salary_eur), n.valid_from, n.valid_to
FROM contract_native FOR SYSTEM_TIME AS OF TIMESTAMP @known_at AS n
         JOIN player AS p ON p.player_id = n.player_id
         JOIN club   AS c ON c.club_id   = n.club_id;
CALL sp_a2_compare('Q5 at 2025-09-15 12:00 (wrong loan believed)');

-- 15 sep 17:00, after the retraction, 69 rows
UPDATE query_params SET known_at = '2025-09-15 17:00:00' WHERE id = 1;
SET @known_at = (SELECT known_at FROM query_params WHERE id = 1);
INSERT INTO a2_core
SELECT 'CONTRACT', CONCAT(first_name, ' ', last_name), club,
       CONCAT(contract_type, ' ', salary_eur), valid_from, valid_to
FROM v_q5_contracts_believed_at;
INSERT INTO a2_native
SELECT 'CONTRACT', CONCAT(p.first_name, ' ', p.last_name), c.short_code,
       CONCAT(n.contract_type, ' ', n.salary_eur), n.valid_from, n.valid_to
FROM contract_native FOR SYSTEM_TIME AS OF TIMESTAMP @known_at AS n
         JOIN player AS p ON p.player_id = n.player_id
         JOIN club   AS c ON c.club_id   = n.club_id;
CALL sp_a2_compare('Q5 at 2025-09-15 17:00 (after retraction)');

-- 20 mar 2026, between S19 and S20
UPDATE query_params SET known_at = '2026-03-20 00:00:00' WHERE id = 1;
SET @known_at = (SELECT known_at FROM query_params WHERE id = 1);
INSERT INTO a2_core
SELECT 'CONTRACT', CONCAT(first_name, ' ', last_name), club,
       CONCAT(contract_type, ' ', salary_eur), valid_from, valid_to
FROM v_q5_contracts_believed_at;
INSERT INTO a2_native
SELECT 'CONTRACT', CONCAT(p.first_name, ' ', p.last_name), c.short_code,
       CONCAT(n.contract_type, ' ', n.salary_eur), n.valid_from, n.valid_to
FROM contract_native FOR SYSTEM_TIME AS OF TIMESTAMP @known_at AS n
         JOIN player AS p ON p.player_id = n.player_id
         JOIN club   AS c ON c.club_id   = n.club_id;
CALL sp_a2_compare('Q5 at 2026-03-20');


-- ---------- Q6 native: HAR on 4 mar 2026 ----------
-- "today" is AS OF CURRENT_TIMESTAMP(6) here, known_at = 9999-12-31 in the core view

SET @club = 3, @valid_at = '2026-03-04';

-- three answers: Romano / Kelly / Romano
SELECT '2026-03-10' AS known_at, CONCAT(co.first_name, ' ', co.last_name) AS head_coach
FROM head_coach_native FOR SYSTEM_TIME AS OF TIMESTAMP '2026-03-10 00:00:00' AS h
         JOIN coach AS co ON co.coach_id = h.coach_id
WHERE h.club_id = @club AND h.valid_from <= @valid_at AND @valid_at < h.valid_to
UNION ALL
SELECT '2026-03-20', CONCAT(co.first_name, ' ', co.last_name)
FROM head_coach_native FOR SYSTEM_TIME AS OF TIMESTAMP '2026-03-20 00:00:00' AS h
         JOIN coach AS co ON co.coach_id = h.coach_id
WHERE h.club_id = @club AND h.valid_from <= @valid_at AND @valid_at < h.valid_to
UNION ALL
SELECT 'today', CONCAT(co.first_name, ' ', co.last_name)
FROM head_coach_native FOR SYSTEM_TIME AS OF CURRENT_TIMESTAMP(6) AS h
         JOIN coach AS co ON co.coach_id = h.coach_id
WHERE h.club_id = @club AND h.valid_from <= @valid_at AND @valid_at < h.valid_to;

-- full Q6 (coach + squad) vs the core view
-- known 10 mar
UPDATE query_params
SET subject_id = 3, valid_at = '2026-03-04', known_at = '2026-03-10 00:00:00'
WHERE id = 1;
SET @known_at = (SELECT known_at FROM query_params WHERE id = 1);
INSERT INTO a2_core
SELECT fact, person, club, details, valid_from, valid_to FROM v_q6_club_as_of;
INSERT INTO a2_native
SELECT 'HEAD COACH', CONCAT(co.first_name, ' ', co.last_name), c.short_code, NULL,
       h.valid_from, h.valid_to
FROM head_coach_native FOR SYSTEM_TIME AS OF TIMESTAMP @known_at AS h
         JOIN coach AS co ON co.coach_id = h.coach_id
         JOIN club  AS c  ON c.club_id   = h.club_id
WHERE h.club_id = @club AND h.valid_from <= @valid_at AND @valid_at < h.valid_to
UNION ALL
SELECT 'PLAYER', CONCAT(p.first_name, ' ', p.last_name), c.short_code,
       CONCAT(n.contract_type, ' ', n.salary_eur), n.valid_from, n.valid_to
FROM contract_native FOR SYSTEM_TIME AS OF TIMESTAMP @known_at AS n
         JOIN player AS p ON p.player_id = n.player_id
         JOIN club   AS c ON c.club_id   = n.club_id
WHERE n.club_id = @club AND n.valid_from <= @valid_at AND @valid_at < n.valid_to;
CALL sp_a2_compare('Q6 HAR on 2026-03-04, known 2026-03-10');

-- known 20 mar
UPDATE query_params SET known_at = '2026-03-20 00:00:00' WHERE id = 1;
SET @known_at = (SELECT known_at FROM query_params WHERE id = 1);
INSERT INTO a2_core
SELECT fact, person, club, details, valid_from, valid_to FROM v_q6_club_as_of;
INSERT INTO a2_native
SELECT 'HEAD COACH', CONCAT(co.first_name, ' ', co.last_name), c.short_code, NULL,
       h.valid_from, h.valid_to
FROM head_coach_native FOR SYSTEM_TIME AS OF TIMESTAMP @known_at AS h
         JOIN coach AS co ON co.coach_id = h.coach_id
         JOIN club  AS c  ON c.club_id   = h.club_id
WHERE h.club_id = @club AND h.valid_from <= @valid_at AND @valid_at < h.valid_to
UNION ALL
SELECT 'PLAYER', CONCAT(p.first_name, ' ', p.last_name), c.short_code,
       CONCAT(n.contract_type, ' ', n.salary_eur), n.valid_from, n.valid_to
FROM contract_native FOR SYSTEM_TIME AS OF TIMESTAMP @known_at AS n
         JOIN player AS p ON p.player_id = n.player_id
         JOIN club   AS c ON c.club_id   = n.club_id
WHERE n.club_id = @club AND n.valid_from <= @valid_at AND @valid_at < n.valid_to;
CALL sp_a2_compare('Q6 HAR on 2026-03-04, known 2026-03-20');

-- known today
UPDATE query_params SET known_at = '9999-12-31 00:00:00' WHERE id = 1;
INSERT INTO a2_core
SELECT fact, person, club, details, valid_from, valid_to FROM v_q6_club_as_of;
INSERT INTO a2_native
SELECT 'HEAD COACH', CONCAT(co.first_name, ' ', co.last_name), c.short_code, NULL,
       h.valid_from, h.valid_to
FROM head_coach_native FOR SYSTEM_TIME AS OF CURRENT_TIMESTAMP(6) AS h
         JOIN coach AS co ON co.coach_id = h.coach_id
         JOIN club  AS c  ON c.club_id   = h.club_id
WHERE h.club_id = @club AND h.valid_from <= @valid_at AND @valid_at < h.valid_to
UNION ALL
SELECT 'PLAYER', CONCAT(p.first_name, ' ', p.last_name), c.short_code,
       CONCAT(n.contract_type, ' ', n.salary_eur), n.valid_from, n.valid_to
FROM contract_native FOR SYSTEM_TIME AS OF CURRENT_TIMESTAMP(6) AS n
         JOIN player AS p ON p.player_id = n.player_id
         JOIN club   AS c ON c.club_id   = n.club_id
WHERE n.club_id = @club AND n.valid_from <= @valid_at AND @valid_at < n.valid_to;
CALL sp_a2_compare('Q6 HAR on 2026-03-04, known today');


-- ---------- what the engine does for us (all rolled back) ----------

-- helper: runs a statement, shows the error, rolls back
DELIMITER //
CREATE PROCEDURE sp_a2_try(IN p_attempt VARCHAR(200), IN p_sql TEXT)
BEGIN
    DECLARE v_msg TEXT DEFAULT NULL;
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
        GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
    SET @a2_sql = p_sql;
    START TRANSACTION;
    PREPARE stmt FROM @a2_sql;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;
    ROLLBACK;
    SELECT p_attempt                                   AS attempt,
           IF(v_msg IS NULL, 'NOT BLOCKED', 'blocked') AS result,
           v_msg                                       AS error_message;
END//
DELIMITER ;

-- WITHOUT OVERLAPS blocks I1 and I3 violations, both should say blocked
CALL sp_a2_try('I1 native: second NOR contract for Walsh overlapping his current one',
               'INSERT INTO contract_native (player_id, club_id, contract_type, salary_eur, valid_from, valid_to) VALUES (1, 1, ''PERMANENT'', 1000, ''2026-02-01'', ''2026-03-01'')');

CALL sp_a2_try('I3 native: a second head coach for HAR at the same time',
               'INSERT INTO head_coach_native (club_id, coach_id, valid_from, valid_to) VALUES (3, 7, ''2026-05-01'', ''9999-12-31'')');

-- FOR PORTION OF splits the row by itself and versioning keeps the old one,
-- i.e. the close + insert we do by hand. Walsh 1.2M only sep-dec 2026.
START TRANSACTION;

UPDATE contract_native
    FOR PORTION OF valid_period FROM '2026-09-01' TO '2027-01-01'
SET   salary_eur = 1200000.00
WHERE player_id = 1 AND club_id = 1;

-- Walsh: split in 3 + the replaced row kept as history
SELECT player_id, club_id, salary_eur, valid_from, valid_to, row_start, row_end,
       IF(row_end > CURRENT_TIMESTAMP(6), 'current', 'history') AS state
FROM contract_native FOR SYSTEM_TIME ALL
WHERE player_id = 1
ORDER BY row_start, valid_from;

ROLLBACK;