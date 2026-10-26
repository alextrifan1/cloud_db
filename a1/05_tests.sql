-- 05_tests.sql
-- Runs every view (Q0-Q8) with concrete inputs.
-- Run after 01-04. Each test: set the inputs, then read the view.
-- The expected result is written above each SELECT.
-- Results that use today's date (Q1, Q2 tenure_days) were checked on 2026-10-24.

USE football_bt;
SET time_zone = '+00:00';


-- =====================================================================
-- Q0 | Integrity violations
-- =====================================================================

-- Q0.a: final data. Expect 0 rows.
SELECT * FROM v_integrity_violations;

-- Q0.b: break three rows on purpose, read the view, then undo.
-- Expect 3 rows, one per rule:
--   I1  a second NOR contract for player 1 overlapping his real one
--   I3  Larsen as a second HAR head coach next to Kelly
--   I2  a contract for player 68 at RIV that starts before the league exists
START TRANSACTION;

INSERT INTO contract_version (player_id, club_id, contract_type, salary_eur, valid_from, tx_from, tx_id)
VALUES (1, 1, 'PERMANENT', 1000.00, '2026-02-01', '2026-06-01 00:00:00', 1);

INSERT INTO head_coach_version (club_id, coach_id, valid_from, tx_from, tx_id)
VALUES (3, 7, '2026-05-01', '2026-06-01 00:00:00', 1);

INSERT INTO contract_version (player_id, club_id, contract_type, salary_eur, valid_from, valid_to, tx_from, tx_id)
VALUES (68, 2, 'PERMANENT', 1000.00, '2025-06-01', '2025-08-01', '2026-06-01 00:00:00', 1);

-- Q0.b break test: 3 rows (I1, I3, I2)
SELECT * FROM v_integrity_violations;

ROLLBACK;

-- Q0.c: after the rollback. Expect 0 rows again.
SELECT * FROM v_integrity_violations;


-- =====================================================================
-- Q1 | Current contracts of one player
-- =====================================================================

-- Q1.a: Moreau (13). Raise at RIV (S22), then NOR from 1 Jul 2026 (S23).
-- Expect 1 row: NOR, PERMANENT, 800,000, from 2026-07-01
UPDATE query_params SET subject_id = 13 WHERE id = 1;
-- Q1.a Moreau (13): NOR 800,000
SELECT * FROM v_q1_player_contracts_now;

-- Q1.b: Hughes (12). His RIV loan ended 1 Jul 2026, only WES is left.
-- Expect 1 row: WES, PERMANENT, 600,000, from 2025-09-01
UPDATE query_params SET subject_id = 12 WHERE id = 1;
-- Q1.b Hughes (12): WES 600,000
SELECT * FROM v_q1_player_contracts_now;

-- Q1.c: Rossi (56). The loan entered by mistake (S6, S7) must not show.
-- Expect 1 row: SOU, PERMANENT, 400,000, from 2025-07-01
UPDATE query_params SET subject_id = 56 WHERE id = 1;
-- Q1.c Rossi (56): SOU only, no retracted loan
SELECT * FROM v_q1_player_contracts_now;

-- Q1.d: Ward (68), never signed. Expect 0 rows.
UPDATE query_params SET subject_id = 68 WHERE id = 1;
-- Q1.d Ward (68): 0 rows
SELECT * FROM v_q1_player_contracts_now;


-- =====================================================================
-- Q2 | Head coach tenures of one club, as known today
-- =====================================================================

-- Q2.a: HAR (3). The corrected date (S20) is used, not the S19 one.
-- Expect 2 rows: Romano 2025-07-01 -> 2026-03-06 (248 days),
--                Kelly  2026-03-06 -> open, still in charge
UPDATE query_params SET subject_id = 3 WHERE id = 1;
-- Q2.a HAR: Romano, then Kelly
SELECT * FROM v_q2_head_coach_history;

-- Q2.b: RIV (2). Expect Weber -> 2025-10-06 (97 days), then Larsen.
UPDATE query_params SET subject_id = 2 WHERE id = 1;
-- Q2.b RIV: Weber, then Larsen
SELECT * FROM v_q2_head_coach_history;

-- Q2.c: WES (5). Expect Ortiz -> 2026-04-01 (274 days), then Weber.
UPDATE query_params SET subject_id = 5 WHERE id = 1;
-- Q2.c WES: Ortiz, then Weber
SELECT * FROM v_q2_head_coach_history;

-- Q2.d: merging. Our data never stores one tenure in two rows, so we
-- split Kelly's row in two (closed and re-inserted, as a real change
-- would do), read the view, then undo.
-- Expect Kelly as ONE tenure from 2026-03-06, rows_merged = 2.
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
-- Q2.d merge test: Kelly as one tenure, rows_merged = 2
SELECT * FROM v_q2_head_coach_history;

ROLLBACK;


-- =====================================================================
-- Q3 | Late entries, proactive entries and corrections
-- =====================================================================

-- Q3.a: the full list, in the order the changes were recorded.
-- Expect 32 rows. Every E2, E3 and E4 event from the story log appears.

-- Q3.a full list: 32 rows
SELECT * FROM v_q3_late_proactive_corrections
ORDER BY recorded_at, table_name, subject;

-- Q3.b: summary per label. Expect:
--   CORRECTION (E4)   3  S9, S18, S20
--   LATE (E3)         7  S5, S15, S17, S19, S22
--   PROACTIVE (E2)   21  S2, S4, S11, S12, S14, S16, S23
--   RETRACTION (E8)   1  S7

-- Q3.b summary per label
SELECT classification,
       COUNT(*) AS rows_found,
       GROUP_CONCAT(DISTINCT story_event ORDER BY recorded_at) AS story_events
FROM v_q3_late_proactive_corrections
GROUP BY classification;


-- =====================================================================
-- Q4 | Contracts valid during a named period
-- The period is picked by name from season_period.
-- =====================================================================

-- Q4.a: 2025/26 Autumn. Expect 69 rows, 63 of them "throughout".
-- Not throughout: Cole and Hughes (left), Meyer (released),
-- Martin and Hughes at WES (joined late), Fischer's loan.
UPDATE query_params AS qp
    JOIN   season_period AS sp ON sp.name = '2025/26 Autumn'
SET    qp.period_start = sp.start_date,
       qp.period_end   = sp.end_date
WHERE  qp.id = 1;
-- Q4.a Autumn: list, 69 rows
SELECT * FROM v_q4_contracts_in_period ORDER BY club, last_name;
-- Q4.a Autumn: count 69 / 63
SELECT COUNT(*) AS at_some_point, SUM(throughout = 'yes') AS throughout
FROM v_q4_contracts_in_period;

-- Q4.b: 2025/26 Spring. Expect 70 rows, 64 of them "throughout".
-- Moreau at RIV counts as throughout: his raise on 1 Mar splits the
-- rows, but the view merges them first.
UPDATE query_params AS qp
    JOIN   season_period AS sp ON sp.name = '2025/26 Spring'
SET    qp.period_start = sp.start_date,
       qp.period_end   = sp.end_date
WHERE  qp.id = 1;
-- Q4.b Spring: list, 70 rows
SELECT * FROM v_q4_contracts_in_period ORDER BY club, last_name;
-- Q4.b Spring: count 70 / 64
SELECT COUNT(*) AS at_some_point, SUM(throughout = 'yes') AS throughout
FROM v_q4_contracts_in_period;


-- =====================================================================
-- Q5 | The contract table as the database believed it at known_at
-- =====================================================================

-- Q5.a: go-live afternoon. Only the initial load exists. Expect 66.
UPDATE query_params SET known_at = '2025-07-01 12:00:00' WHERE id = 1;
-- Q5.a 1 Jul 12:00: 66 believed
SELECT COUNT(*) AS contracts_believed FROM v_q5_contracts_believed_at;

-- Q5.b: 15 Sep 12:00, between the mistake (S6, 08:00) and its
-- retraction (S7, 16:30). The wrong loan IS believed.
-- Expect 70 in total; Rossi (56) shows SOU PERMANENT + NOR LOAN.
UPDATE query_params SET known_at = '2025-09-15 12:00:00' WHERE id = 1;
-- Q5.b 15 Sep 12:00: 70 believed
SELECT COUNT(*) AS contracts_believed FROM v_q5_contracts_believed_at;
-- Q5.b Rossi at 12:00: SOU + NOR loan
SELECT * FROM v_q5_contracts_believed_at WHERE player_id = 56;

-- Q5.c: same day 17:00, after the retraction.
-- Expect 69; Rossi (56) shows only SOU.
UPDATE query_params SET known_at = '2025-09-15 17:00:00' WHERE id = 1;
-- Q5.c 15 Sep 17:00: 69 believed
SELECT COUNT(*) AS contracts_believed FROM v_q5_contracts_believed_at;
-- Q5.c Rossi at 17:00: SOU only
SELECT * FROM v_q5_contracts_believed_at WHERE player_id = 56;

-- Q5.d: Cole (23) one second before and right at S3 (5 Aug 11:00).
-- Before: valid_to = 9999-12-31. At S3: valid_to = 2025-08-04.
UPDATE query_params SET known_at = '2025-08-05 10:59:59' WHERE id = 1;
-- Q5.d Cole at 10:59:59: valid_to 9999-12-31
SELECT * FROM v_q5_contracts_believed_at WHERE player_id = 23;
UPDATE query_params SET known_at = '2025-08-05 11:00:00' WHERE id = 1;
-- Q5.d Cole at 11:00: valid_to 2025-08-04
SELECT * FROM v_q5_contracts_believed_at WHERE player_id = 23;


-- =====================================================================
-- Q6 | One club on valid_at, as known at known_at
-- The three-answers case: who coached HAR on 4 March 2026?
-- =====================================================================

-- Q6.a: known on 10 March, before S19 was recorded.
-- Expect HEAD COACH = Luca Romano (open-ended row from go-live).
UPDATE query_params
SET subject_id = 3, valid_at = '2026-03-04', known_at = '2026-03-10 00:00:00'
WHERE id = 1;
-- Q6.a known 10 Mar: Romano
SELECT * FROM v_q6_club_as_of WHERE fact = 'HEAD COACH';

-- Q6.b: known on 20 March, after S19 ("Kelly from 2 Mar"), before S20.
-- Expect HEAD COACH = Sam Kelly.
UPDATE query_params SET known_at = '2026-03-20 00:00:00' WHERE id = 1;
-- Q6.b known 20 Mar: Kelly
SELECT * FROM v_q6_club_as_of WHERE fact = 'HEAD COACH';

-- Q6.c: known today, after S20 moved the handover to 6 Mar.
-- Expect HEAD COACH = Luca Romano (row ending 2026-03-06).
UPDATE query_params SET known_at = '9999-12-31 00:00:00' WHERE id = 1;
-- Q6.c known today: Romano
SELECT * FROM v_q6_club_as_of WHERE fact = 'HEAD COACH';

-- Q6.d: the full picture for 20 March: coach + squad.
-- Expect 13 rows: Kelly + 12 players.
UPDATE query_params SET known_at = '2026-03-20 00:00:00' WHERE id = 1;
-- Q6.d HAR on 4 Mar, known 20 Mar: Kelly + 12 players
SELECT * FROM v_q6_club_as_of ORDER BY fact, person;

-- Q6.e: EXPLAIN, for the report (Part A).
-- With the index: cv uses ix_contract_club_asof, type = ref.

-- Q6.e EXPLAIN of the view
EXPLAIN SELECT * FROM v_q6_club_as_of;

-- The contract part of Q6 on its own, with and without the index.
-- With:    type = ref, key = ix_contract_club_asof

-- Q6.f EXPLAIN with index: ref
EXPLAIN
SELECT cv.*
FROM contract_version AS cv
         CROSS JOIN query_params AS qp
WHERE cv.club_id    = qp.subject_id
  AND cv.valid_from <= qp.valid_at AND qp.valid_at < cv.valid_to
  AND cv.tx_from    <= qp.known_at AND qp.known_at < cv.tx_to;

-- Without: type = ALL (reads the whole table)

-- Q6.g EXPLAIN without index: ALL
EXPLAIN
SELECT cv.*
FROM contract_version AS cv IGNORE INDEX (ix_contract_club_asof)
         CROSS JOIN query_params AS qp
WHERE cv.club_id    = qp.subject_id
  AND cv.valid_from <= qp.valid_at AND qp.valid_at < cv.valid_to
  AND cv.tx_from    <= qp.known_at AND qp.known_at < cv.tx_to;


-- =====================================================================
-- Q7 | Active players per club per month, as known today
-- =====================================================================

-- Q7.a: all clubs. Expect 72 rows (12 months x 6 clubs).
SELECT * FROM v_q7_monthly_active ORDER BY club, month;

-- Q7.b: SOU. Expect 12 players Aug-Nov (Fischer on loan), 11 in Dec-Jan
-- (Meyer released, Fischer still there until 15 Jan), 11 from Feb
-- (Meyer back). on_loan_in shows 0 from February.

-- Q7.b SOU per month
SELECT * FROM v_q7_monthly_active WHERE club = 'SOU' ORDER BY month;


-- =====================================================================
-- Q8 | Gaps before a player rejoins the same club
-- =====================================================================

-- Expect exactly the three E6 events:
--   Cole   HAR  2025-08-04 -> 2026-01-10  159 days
--   Hughes RIV  2025-09-01 -> 2026-01-20  141 days (comes back on loan)
--   Meyer  SOU  2025-11-30 -> 2026-02-10   72 days

-- Q8 rejoin gaps: Cole, Hughes, Meyer
SELECT * FROM v_q8_rejoin_gaps ORDER BY last_name;