-- 05_tests.sql: runs every view with test inputs (after 01-04)
-- expected results are next to each query
-- Q1 and Q2 day counts depend on today's date

USE football_bt;
SET time_zone = '+00:00';


-- ---------- Q0 integrity ----------

-- Q0.a no violations
SELECT * FROM v_integrity_violations;

-- Q0.b: insert 3 bad rows (I1, I3, I2), check the view, rollback
START TRANSACTION;

INSERT INTO contract_version (player_id, club_id, contract_type, salary_eur, valid_from, tx_from, tx_id)
VALUES (1, 1, 'PERMANENT', 1000.00, '2026-02-01', '2026-06-01 00:00:00', 1);

INSERT INTO head_coach_version (club_id, coach_id, valid_from, tx_from, tx_id)
VALUES (3, 7, '2026-05-01', '2026-06-01 00:00:00', 1);

INSERT INTO contract_version (player_id, club_id, contract_type, salary_eur, valid_from, valid_to, tx_from, tx_id)
VALUES (68, 2, 'PERMANENT', 1000.00, '2025-06-01', '2025-08-01', '2026-06-01 00:00:00', 1);

-- Q0.b should show I1, I3, I2
SELECT * FROM v_integrity_violations;

ROLLBACK;

-- Q0.c empty again
SELECT * FROM v_integrity_violations;


-- ---------- Q1 current contracts ----------

UPDATE query_params SET subject_id = 13 WHERE id = 1;
-- Q1.a Moreau: NOR 800k from 1 jul 2026
SELECT * FROM v_q1_player_contracts_now;

UPDATE query_params SET subject_id = 12 WHERE id = 1;
-- Q1.b Hughes: only WES (RIV loan is over)
SELECT * FROM v_q1_player_contracts_now;

UPDATE query_params SET subject_id = 56 WHERE id = 1;
-- Q1.c Rossi: only SOU, retracted loan not shown
SELECT * FROM v_q1_player_contracts_now;

UPDATE query_params SET subject_id = 68 WHERE id = 1;
-- Q1.d Ward: no contract, 0 rows
SELECT * FROM v_q1_player_contracts_now;


-- ---------- Q2 coach tenures (as known today) ----------

UPDATE query_params SET subject_id = 3 WHERE id = 1;
-- Q2.a HAR: Romano 248 days, then Kelly (S20 date)
SELECT * FROM v_q2_head_coach_history;

UPDATE query_params SET subject_id = 2 WHERE id = 1;
-- Q2.b RIV: Weber 97 days, then Larsen
SELECT * FROM v_q2_head_coach_history;

UPDATE query_params SET subject_id = 5 WHERE id = 1;
-- Q2.c WES: Ortiz 274 days, then Weber
SELECT * FROM v_q2_head_coach_history;

-- Q2.d: split Kelly's row in two to test the merge, then rollback
START TRANSACTION;

SET @t = '2026-06-01 00:00:00';
INSERT INTO tx_registry (tx_time, author, reason) VALUES (@t, 'test', 'Q2 merge test');
SET @id = LAST_INSERT_ID();

UPDATE head_coach_version
SET    tx_to = @t
WHERE  club_id = 3 AND coach_id = 8
  AND  tx_to = '9999-12-31 23:59:59.999999';

INSERT INTO head_coach_version (club_id, coach_id, valid_from, valid_to, tx_from, tx_id) VALUES
                                                                                             (3, 8, '2026-03-06', '2026-06-01', @t, @id),
                                                                                             (3, 8, '2026-06-01', '9999-12-31', @t, @id);

UPDATE query_params SET subject_id = 3 WHERE id = 1;
-- Q2.d Kelly still one tenure, rows_merged = 2
SELECT * FROM v_q2_head_coach_history;

ROLLBACK;


-- ---------- Q3 late / proactive / corrections ----------

-- Q3.a all 32 rows
SELECT * FROM v_q3_late_proactive_corrections
ORDER BY recorded_at, table_name, subject;

-- Q3.b per label: E4 3, E3 7, E2 21, E8 1
SELECT classification,
       COUNT(*) AS rows_found,
       GROUP_CONCAT(DISTINCT story_event ORDER BY recorded_at) AS story_events
FROM v_q3_late_proactive_corrections
GROUP BY classification;

-- Q3.c corrections, old vs new
SELECT story_event, change_date, delay_days, classification, old_belief, new_belief
FROM v_q3_late_proactive_corrections
WHERE classification = 'CORRECTION (E4)'
ORDER BY recorded_at;


-- ---------- Q4 contracts in a named period ----------

UPDATE query_params AS qp
    JOIN   season_period AS sp ON sp.name = '2025/26 Autumn'
SET    qp.period_start = sp.start_date,
       qp.period_end   = sp.end_date
WHERE  qp.id = 1;
-- Q4.a Autumn list
SELECT * FROM v_q4_contracts_in_period ORDER BY club, last_name;
-- Q4.a Autumn: 69 / 63
SELECT COUNT(*) AS at_some_point, SUM(throughout = 'yes') AS throughout
FROM v_q4_contracts_in_period;

UPDATE query_params AS qp
    JOIN   season_period AS sp ON sp.name = '2025/26 Spring'
SET    qp.period_start = sp.start_date,
       qp.period_end   = sp.end_date
WHERE  qp.id = 1;
-- Q4.b Spring list
SELECT * FROM v_q4_contracts_in_period ORDER BY club, last_name;
-- Q4.b Spring: 70 / 64 (Moreau counts as throughout)
SELECT COUNT(*) AS at_some_point, SUM(throughout = 'yes') AS throughout
FROM v_q4_contracts_in_period;


-- ---------- Q5 what the db believed at known_at ----------

UPDATE query_params SET known_at = '2025-07-01 12:00:00' WHERE id = 1;
-- Q5.a go-live: 66
SELECT COUNT(*) AS contracts_believed FROM v_q5_contracts_believed_at;

UPDATE query_params SET known_at = '2025-09-15 12:00:00' WHERE id = 1;
-- Q5.b 15 sep 12:00: 70 (wrong loan still believed)
SELECT COUNT(*) AS contracts_believed FROM v_q5_contracts_believed_at;
-- Q5.b Rossi at 12:00: SOU + NOR loan
SELECT * FROM v_q5_contracts_believed_at WHERE player_id = 56;

UPDATE query_params SET known_at = '2025-09-15 17:00:00' WHERE id = 1;
-- Q5.c 15 sep 17:00: 69
SELECT COUNT(*) AS contracts_believed FROM v_q5_contracts_believed_at;
-- Q5.c Rossi at 17:00: SOU only
SELECT * FROM v_q5_contracts_believed_at WHERE player_id = 56;

UPDATE query_params SET known_at = '2025-08-05 10:59:59' WHERE id = 1;
-- Q5.d Cole just before S3: valid_to 9999-12-31
SELECT * FROM v_q5_contracts_believed_at WHERE player_id = 23;
UPDATE query_params SET known_at = '2025-08-05 11:00:00' WHERE id = 1;
-- Q5.d Cole at S3: valid_to 2025-08-04
SELECT * FROM v_q5_contracts_believed_at WHERE player_id = 23;


-- ---------- Q6 HAR on 4 mar 2026, three answers ----------

UPDATE query_params
SET subject_id = 3, valid_at = '2026-03-04', known_at = '2026-03-10 00:00:00'
WHERE id = 1;
-- Q6.a known 10 mar: Romano
SELECT * FROM v_q6_club_as_of WHERE fact = 'HEAD COACH';

UPDATE query_params SET known_at = '2026-03-20 00:00:00' WHERE id = 1;
-- Q6.b known 20 mar: Kelly
SELECT * FROM v_q6_club_as_of WHERE fact = 'HEAD COACH';

UPDATE query_params SET known_at = '9999-12-31 00:00:00' WHERE id = 1;
-- Q6.c known today: Romano
SELECT * FROM v_q6_club_as_of WHERE fact = 'HEAD COACH';

UPDATE query_params SET known_at = '2026-03-20 00:00:00' WHERE id = 1;
-- Q6.d 20 mar: Kelly + 12 players
SELECT * FROM v_q6_club_as_of ORDER BY fact, person;

-- Q6.e explain of the view
EXPLAIN SELECT * FROM v_q6_club_as_of;

-- Q6.f explain with index (ref)
EXPLAIN
SELECT cv.*
FROM contract_version AS cv
         CROSS JOIN query_params AS qp
WHERE cv.club_id    = qp.subject_id
  AND cv.valid_from <= qp.valid_at AND qp.valid_at < cv.valid_to
  AND cv.tx_from    <= qp.known_at AND qp.known_at < cv.tx_to;

-- Q6.g explain without index (ALL)
EXPLAIN
SELECT cv.*
FROM contract_version AS cv IGNORE INDEX (ix_contract_club_asof)
         CROSS JOIN query_params AS qp
WHERE cv.club_id    = qp.subject_id
  AND cv.valid_from <= qp.valid_at AND qp.valid_at < cv.valid_to
  AND cv.tx_from    <= qp.known_at AND qp.known_at < cv.tx_to;


-- ---------- Q7 players per club per month ----------

-- Q7.a all clubs, 72 rows
SELECT * FROM v_q7_monthly_active ORDER BY club, month;

-- Q7.b SOU: 12 aug-nov, on_loan_in 0 from feb
SELECT * FROM v_q7_monthly_active WHERE club = 'SOU' ORDER BY month;


-- ---------- Q8 rejoin gaps ----------

-- Q8 Cole 159, Hughes 141, Meyer 72
SELECT * FROM v_q8_rejoin_gaps ORDER BY last_name;