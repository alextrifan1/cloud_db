-- =====================================================================
-- 03_timeline.sql
-- Every change after go-live, in transaction-time order.
-- Run after 01_schema.sql and 02_data.sql.
--
-- Labels:  S1..S23 = story events (see the story log in README.md)
--          E1..E9  = assignment event types
--
-- Every event follows the same skeleton:
--   1. START TRANSACTION
--   2. SET @sim_now          -> the simulated "now" for this change
--   3. INSERT tx_registry    -> one row = one logical change
--      SET @tx_id            -> remember its id
--   4. The change itself, using one of three patterns:
--        INSERT only         -> a brand-new fact
--        CLOSE + INSERT      -> a fact changed or was corrected
--        CLOSE only          -> a fact was never true (retraction)
--      "CLOSE" = UPDATE ... SET tx_to = @sim_now on the current row.
--      This is the ONLY kind of UPDATE allowed (rule 6).
--   5. COMMIT
-- =====================================================================

USE football_bt;
SET time_zone = '+00:00';

-- Sentinels, so we never mistype them below
SET @valid_open = '9999-12-31';
SET @tx_open    = '9999-12-31 23:59:59.999999';


-- ---------------------------------------------------------------------
-- S2 | E2 proactive: free agent Leo Martin (67) signs for HAR (3)
-- Recorded 2025-07-10, valid from 2025-07-15 (5 days in the future)
-- Pattern: INSERT only
-- ---------------------------------------------------------------------
START TRANSACTION;

SET @sim_now = '2025-07-10 10:00:00';

INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'clerk_ana', 'S2 | E2 proactive: Martin signs for HAR from 15 Jul');
SET @tx_id = LAST_INSERT_ID();

INSERT INTO contract_version
  (player_id, club_id, contract_type, salary_eur, valid_from, tx_from, tx_id)
VALUES
  (67, 3, 'PERMANENT', 330000.00, '2025-07-15', @sim_now, @tx_id);

COMMIT;


-- ---------------------------------------------------------------------
-- S3 | E5 real-world end: Ryan Cole (23) leaves HAR (3)
-- Last day at the club: 3 Aug -> valid_to = 2025-08-04 (half-open)
-- Recorded 2025-08-05
-- Pattern: CLOSE + INSERT
-- ---------------------------------------------------------------------
START TRANSACTION;

SET @sim_now = '2025-08-05 11:00:00';

INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'clerk_ana', 'S3 | E5 end: Cole leaves HAR, contract terminated by mutual consent');
SET @tx_id = LAST_INSERT_ID();

-- (a) CLOSE: stop believing "Cole is at HAR forever"
UPDATE contract_version
SET    tx_to = @sim_now
WHERE  player_id = 23
  AND  club_id   = 3
  AND  tx_to     = @tx_open                  -- the current belief
  AND  valid_to  = @valid_open;              -- the open-ended contract

-- (b) INSERT: the new belief "Cole was at HAR from 1 Jul until 4 Aug"
INSERT INTO contract_version
  (player_id, club_id, contract_type, salary_eur, valid_from, valid_to, tx_from, tx_id)
VALUES
  (23, 3, 'PERMANENT', 490000.00, '2025-07-01', '2025-08-04', @sim_now, @tx_id);

COMMIT;


-- ---------------------------------------------------------------------
-- S4 | E2 proactive + E9 multi-table:
-- Max Fischer (34) loaned from EAS (4) to SOU (6),
-- valid 2025-08-25 -> 2026-07-01, recorded 2025-08-20.
-- Same transaction: SOU's budget drops by the 300,000 loan fee
-- from 2025-08-25 (5,800,000 -> 5,500,000).
-- His PERMANENT contract at EAS is NOT touched: it keeps running.
-- Patterns: INSERT only (loan) + CLOSE + INSERT (budget)
-- ---------------------------------------------------------------------
START TRANSACTION;

SET @sim_now = '2025-08-20 12:00:00';

INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'clerk_ana', 'S4 | E2+E9: Fischer loaned EAS->SOU from 25 Aug; SOU pays loan fee');
SET @tx_id = LAST_INSERT_ID();

-- Table 1: the loan contract (new fact)
INSERT INTO contract_version
  (player_id, club_id, contract_type, salary_eur, valid_from, valid_to, tx_from, tx_id)
VALUES
  (34, 6, 'LOAN', 250000.00, '2025-08-25', '2026-07-01', @sim_now, @tx_id);

-- Table 2: SOU's budget changes from 25 Aug
-- (a) CLOSE the current belief "SOU has 5,800,000 forever"
UPDATE club_version
SET    tx_to = @sim_now
WHERE  club_id  = 6
  AND  tx_to    = @tx_open
  AND  valid_to = @valid_open;

-- (b) INSERT the new belief, split in two valid periods:
--     old budget until 25 Aug, new budget from 25 Aug
INSERT INTO club_version
  (club_id, name, budget_eur, valid_from, valid_to, tx_from, tx_id)
VALUES
  (6, 'Southport Town', 5800000.00, '2025-07-01', '2025-08-25', @sim_now, @tx_id),
  (6, 'Southport Town', 5500000.00, '2025-08-25', @valid_open,  @sim_now, @tx_id);

COMMIT;


-- ---------------------------------------------------------------------
-- S5 | E3 late entry + E5 end: Sean Hughes (12) transfers RIV (2) -> WES (5)
-- Deadline-day move, valid from 2025-09-01 (last day of the summer window).
-- Registered 2025-09-12: 11 days late, AFTER the window closed.
-- Patterns: CLOSE + INSERT (RIV contract ends) + INSERT (new WES contract)
-- ---------------------------------------------------------------------
START TRANSACTION;

SET @sim_now = '2025-09-12 09:30:00';

INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'clerk_ana', 'S5 | E3+E5: Hughes RIV->WES on 1 Sep, registered after the window closed');
SET @tx_id = LAST_INSERT_ID();

-- (a) CLOSE: stop believing "Hughes is at RIV forever"
UPDATE contract_version
SET    tx_to = @sim_now
WHERE  player_id = 12
  AND  club_id   = 2
  AND  tx_to     = @tx_open
  AND  valid_to  = @valid_open;

-- (b) INSERT: RIV contract now ends on 1 Sep, and the new WES contract starts that day
INSERT INTO contract_version
  (player_id, club_id, contract_type, salary_eur, valid_from, valid_to, tx_from, tx_id)
VALUES
  (12, 2, 'PERMANENT', 560000.00, '2025-07-01', '2025-09-01',  @sim_now, @tx_id),
  (12, 5, 'PERMANENT', 600000.00, '2025-09-01', @valid_open,   @sim_now, @tx_id);

COMMIT;


-- ---------------------------------------------------------------------
-- S6 | (the mistake) A clerk wrongly enters a loan of Nico Rossi (56)
-- from SOU (6) to NOR (1), valid 2025-09-15 -> 2026-07-01.
-- This loan never happened. It is a normal-looking insert;
-- S7 retracts it a few hours later.
-- Pattern: INSERT only
-- ---------------------------------------------------------------------
START TRANSACTION;

SET @sim_now = '2025-09-15 08:00:00';

INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'clerk_bob', 'S6 | Rossi loaned SOU->NOR from 15 Sep (entered by mistake)');
SET @tx_id = LAST_INSERT_ID();

INSERT INTO contract_version
  (player_id, club_id, contract_type, salary_eur, valid_from, valid_to, tx_from, tx_id)
VALUES
  (56, 1, 'LOAN', 300000.00, '2025-09-15', '2026-07-01', @sim_now, @tx_id);

COMMIT;


-- ---------------------------------------------------------------------
-- S7 | E8 retraction ("never true"): the S6 loan is withdrawn.
-- Pattern: CLOSE only - transaction time is closed, NO replacement row.
-- Valid time is not touched: we are not saying the loan ended,
-- we are saying it never existed.
-- ---------------------------------------------------------------------
START TRANSACTION;

SET @sim_now = '2025-09-15 16:30:00';

INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'clerk_ana', 'S7 | E8 retraction: Rossi loan to NOR was never agreed, entered by mistake in S6');
SET @tx_id = LAST_INSERT_ID();

UPDATE contract_version
SET    tx_to = @sim_now
WHERE  player_id = 56
  AND  club_id   = 1
  AND  tx_to     = @tx_open;

-- (no INSERT: that is what makes it a retraction)

COMMIT;


-- ---------------------------------------------------------------------
-- S8 | E7 role change, mid-season: RIV (2) sacks Paul Weber (2);
-- Erik Larsen (7) takes over the same day, 2025-10-06.
-- Recorded the same evening.
-- Pattern: CLOSE + INSERT (split into old holder + new holder)
-- ---------------------------------------------------------------------
START TRANSACTION;

SET @sim_now = '2025-10-06 18:00:00';

INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'clerk_ana', 'S8 | E7: RIV sacks Weber, Larsen head coach from 6 Oct');
SET @tx_id = LAST_INSERT_ID();

-- (a) CLOSE: stop believing "Weber coaches RIV forever"
UPDATE head_coach_version
SET    tx_to = @sim_now
WHERE  club_id  = 2
  AND  tx_to    = @tx_open
  AND  valid_to = @valid_open;

-- (b) INSERT: Weber until 6 Oct, Larsen from 6 Oct
INSERT INTO head_coach_version
  (club_id, coach_id, valid_from, valid_to, tx_from, tx_id)
VALUES
  (2, 2, '2025-07-01', '2025-10-06',  @sim_now, @tx_id),
  (2, 7, '2025-10-06', @valid_open,   @sim_now, @tx_id);

COMMIT;


-- ---------------------------------------------------------------------
-- S9 | E4 correction: Adam Kowalski's (45) salary at WES (5) was typed
-- as 450,000 at go-live. The real value is 540,000, from day one.
-- Recorded 2025-10-20.
-- Pattern: CLOSE + INSERT with the SAME valid period, corrected value.
-- (Compare with a real-world change, which would split the valid period.)
-- ---------------------------------------------------------------------
START TRANSACTION;

SET @sim_now = '2025-10-20 10:00:00';

INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'clerk_ana', 'S9 | E4 correction: Kowalski salary typo 450,000 -> 540,000');
SET @tx_id = LAST_INSERT_ID();

-- (a) CLOSE the wrong belief
UPDATE contract_version
SET    tx_to = @sim_now
WHERE  player_id = 45
  AND  club_id   = 5
  AND  tx_to     = @tx_open
  AND  valid_to  = @valid_open;

-- (b) INSERT the corrected belief: same valid period, right salary
INSERT INTO contract_version
  (player_id, club_id, contract_type, salary_eur, valid_from, valid_to, tx_from, tx_id)
VALUES
  (45, 5, 'PERMANENT', 540000.00, '2025-07-01', @valid_open, @sim_now, @tx_id);

COMMIT;


-- ---------------------------------------------------------------------
-- S10 | E5 real-world end: SOU (6) releases Jonas Meyer (57).
-- Gone from 30 Nov -> valid_to = 2025-11-30. Recorded the same day.
-- Pattern: CLOSE + INSERT
-- ---------------------------------------------------------------------
START TRANSACTION;

SET @sim_now = '2025-11-30 17:00:00';

INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'clerk_ana', 'S10 | E5 end: SOU releases Meyer');
SET @tx_id = LAST_INSERT_ID();

UPDATE contract_version
SET    tx_to = @sim_now
WHERE  player_id = 57
  AND  club_id   = 6
  AND  tx_to     = @tx_open
  AND  valid_to  = @valid_open;

INSERT INTO contract_version
  (player_id, club_id, contract_type, salary_eur, valid_from, valid_to, tx_from, tx_id)
VALUES
  (57, 6, 'PERMANENT', 350000.00, '2025-07-01', '2025-11-30', @sim_now, @tx_id);

COMMIT;


-- ---------------------------------------------------------------------
-- S11 | E2 proactive: 8 NOR (1) players (ids 1-8) get salary raises
-- from 2026-01-01. Recorded 2025-12-15.
-- Pattern: CLOSE + INSERT, done for many rows at once ("set-based"):
--   a temporary table lists who gets what, then 3 statements
--   (close, insert old part, insert new part) handle all 8 players.
-- ---------------------------------------------------------------------
START TRANSACTION;

SET @sim_now = '2025-12-15 10:00:00';

INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'clerk_ana', 'S11 | E2 proactive: salary raises for 8 NOR players from 1 Jan');
SET @tx_id = LAST_INSERT_ID();

-- Helper list: player -> new salary. TEMPORARY = disappears when you disconnect.
DROP TEMPORARY TABLE IF EXISTS tmp_raise;
CREATE TEMPORARY TABLE tmp_raise (
  player_id   INT           NOT NULL PRIMARY KEY,
  new_salary  DECIMAL(12,2) NOT NULL
);
INSERT INTO tmp_raise (player_id, new_salary) VALUES
  (1, 950000.00), (2, 680000.00), (3, 460000.00), (4, 580000.00),
  (5, 420000.00), (6, 790000.00), (7, 340000.00), (8, 520000.00);

-- (a) CLOSE the current open-ended contract of each listed player
UPDATE contract_version AS cv
JOIN   tmp_raise        AS r  ON r.player_id = cv.player_id
SET    cv.tx_to = @sim_now
WHERE  cv.club_id  = 1
  AND  cv.tx_to    = @tx_open
  AND  cv.valid_to = @valid_open;

-- (b) INSERT the old salary, now ending on 1 Jan.
--     Copied from the rows we just closed (they are the ones with tx_to = @sim_now).
INSERT INTO contract_version
  (player_id, club_id, contract_type, salary_eur, valid_from, valid_to, tx_from, tx_id)
SELECT cv.player_id, cv.club_id, cv.contract_type, cv.salary_eur,
       cv.valid_from, '2026-01-01', @sim_now, @tx_id
FROM   contract_version AS cv
JOIN   tmp_raise        AS r  ON r.player_id = cv.player_id
WHERE  cv.club_id = 1
  AND  cv.tx_to   = @sim_now;

-- (c) INSERT the new salary, open-ended from 1 Jan
INSERT INTO contract_version
  (player_id, club_id, contract_type, salary_eur, valid_from, valid_to, tx_from, tx_id)
SELECT cv.player_id, cv.club_id, cv.contract_type, r.new_salary,
       '2026-01-01', @valid_open, @sim_now, @tx_id
FROM   contract_version AS cv
JOIN   tmp_raise        AS r  ON r.player_id = cv.player_id
WHERE  cv.club_id = 1
  AND  cv.tx_to   = @sim_now;

DROP TEMPORARY TABLE tmp_raise;

COMMIT;


-- ---------------------------------------------------------------------
-- S12 | E2 proactive: spring budgets for all 6 clubs from 2026-01-01.
-- Recorded 2025-12-20.
-- Pattern: same set-based CLOSE + INSERT as S11, on club_version.
-- Note SOU's current row starts on 2025-08-25 (from S4); copying
-- valid_from from the closed row keeps that correct automatically.
-- ---------------------------------------------------------------------
START TRANSACTION;

SET @sim_now = '2025-12-20 10:00:00';

INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'league_office', 'S12 | E2 proactive: spring budgets for all clubs from 1 Jan');
SET @tx_id = LAST_INSERT_ID();

DROP TEMPORARY TABLE IF EXISTS tmp_budget;
CREATE TEMPORARY TABLE tmp_budget (
  club_id     INT           NOT NULL PRIMARY KEY,
  new_budget  DECIMAL(14,2) NOT NULL
);
INSERT INTO tmp_budget (club_id, new_budget) VALUES
  (1, 11000000.00), (2, 9000000.00), (3, 8400000.00),
  (4,  7500000.00), (5, 6200000.00), (6, 5600000.00);

-- (a) CLOSE each club's current open-ended version
UPDATE club_version AS cv
JOIN   tmp_budget   AS b  ON b.club_id = cv.club_id
SET    cv.tx_to = @sim_now
WHERE  cv.tx_to    = @tx_open
  AND  cv.valid_to = @valid_open;

-- (b) INSERT the autumn budget, now ending on 1 Jan
INSERT INTO club_version
  (club_id, name, budget_eur, valid_from, valid_to, tx_from, tx_id)
SELECT cv.club_id, cv.name, cv.budget_eur,
       cv.valid_from, '2026-01-01', @sim_now, @tx_id
FROM   club_version AS cv
WHERE  cv.tx_to = @sim_now;

-- (c) INSERT the spring budget, open-ended from 1 Jan
INSERT INTO club_version
  (club_id, name, budget_eur, valid_from, valid_to, tx_from, tx_id)
SELECT cv.club_id, cv.name, b.new_budget,
       '2026-01-01', @valid_open, @sim_now, @tx_id
FROM   club_version AS cv
JOIN   tmp_budget   AS b  ON b.club_id = cv.club_id
WHERE  cv.tx_to = @sim_now;

DROP TEMPORARY TABLE tmp_budget;

COMMIT;


-- ---------------------------------------------------------------------
-- S13 | E5 real-world end, earlier than planned: Max Fischer's (34)
-- loan at SOU (6) is cut short. Planned end 2026-07-01, actual end
-- 2026-01-15. His PERMANENT contract at EAS (4) simply keeps running.
-- Recorded 2026-01-16.
-- Pattern: CLOSE + INSERT (same row, earlier valid_to)
-- ---------------------------------------------------------------------
START TRANSACTION;

SET @sim_now = '2026-01-16 09:00:00';

INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'clerk_ana', 'S13 | E5 end: Fischer loan at SOU cut short, ends 15 Jan');
SET @tx_id = LAST_INSERT_ID();

UPDATE contract_version
SET    tx_to = @sim_now
WHERE  player_id = 34
  AND  club_id   = 6
  AND  tx_to     = @tx_open;          -- his only current row at SOU: the loan

INSERT INTO contract_version
  (player_id, club_id, contract_type, salary_eur, valid_from, valid_to, tx_from, tx_id)
VALUES
  (34, 6, 'LOAN', 250000.00, '2025-08-25', '2026-01-15', @sim_now, @tx_id);

COMMIT;


-- ---------------------------------------------------------------------
-- S14 | E2 proactive + E6 restart after a gap:
-- Sean Hughes (12) returns to RIV (2) on loan from WES (5),
-- valid 2026-01-20 -> 2026-07-01, recorded 2026-01-19.
-- The pair (Hughes, RIV) already had [2025-07-01, 2025-09-01) from S5,
-- so this second period, after a gap, is the restart.
-- His PERMANENT contract at WES keeps running.
-- Pattern: INSERT only
-- ---------------------------------------------------------------------
START TRANSACTION;

SET @sim_now = '2026-01-19 14:00:00';

INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'clerk_ana', 'S14 | E2+E6: Hughes back at RIV on loan from WES, from 20 Jan');
SET @tx_id = LAST_INSERT_ID();

INSERT INTO contract_version
  (player_id, club_id, contract_type, salary_eur, valid_from, valid_to, tx_from, tx_id)
VALUES
  (12, 2, 'LOAN', 280000.00, '2026-01-20', '2026-07-01', @sim_now, @tx_id);

COMMIT;


-- ---------------------------------------------------------------------
-- S15 | E3 late entry + E6 restart after a gap:
-- Ryan Cole (23) rejoins HAR (3) from 2026-01-10.
-- Recorded 2026-01-20: 10 days late.
-- The pair (Cole, HAR) had [2025-07-01, 2025-08-04) from S3; gap until 10 Jan.
-- Pattern: INSERT only
-- ---------------------------------------------------------------------
START TRANSACTION;

SET @sim_now = '2026-01-20 11:00:00';

INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'clerk_ana', 'S15 | E3+E6: Cole rejoins HAR from 10 Jan, recorded 10 days late');
SET @tx_id = LAST_INSERT_ID();

INSERT INTO contract_version
  (player_id, club_id, contract_type, salary_eur, valid_from, tx_from, tx_id)
VALUES
  (23, 3, 'PERMANENT', 420000.00, '2026-01-10', @sim_now, @tx_id);

COMMIT;


-- ---------------------------------------------------------------------
-- S16 | E2 proactive + E6 restart after a gap:
-- Jonas Meyer (57) rejoins SOU (6) from 2026-02-01, recorded 2026-01-28.
-- The pair (Meyer, SOU) had [2025-07-01, 2025-11-30) from S10.
-- NOTE: the date 1 Feb is wrong; S18 corrects it to 10 Feb.
-- Pattern: INSERT only
-- ---------------------------------------------------------------------
START TRANSACTION;

SET @sim_now = '2026-01-28 15:00:00';

INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'clerk_ana', 'S16 | E2+E6: Meyer rejoins SOU from 1 Feb');
SET @tx_id = LAST_INSERT_ID();

INSERT INTO contract_version
  (player_id, club_id, contract_type, salary_eur, valid_from, tx_from, tx_id)
VALUES
  (57, 6, 'PERMANENT', 300000.00, '2026-02-01', @sim_now, @tx_id);

COMMIT;


-- ---------------------------------------------------------------------
-- S17 | E3 late entry + E5 end: Tom Baker (35) transfers EAS (4) -> NOR (1)
-- on 2026-02-01, the last day of the winter window.
-- Registered 2026-02-11: 10 days late, AFTER the window closed.
-- Pattern: CLOSE + INSERT (same shape as S5)
-- ---------------------------------------------------------------------
START TRANSACTION;

SET @sim_now = '2026-02-11 10:00:00';

INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'clerk_ana', 'S17 | E3+E5: Baker EAS->NOR on 1 Feb, registered after the winter window');
SET @tx_id = LAST_INSERT_ID();

-- (a) CLOSE: stop believing "Baker is at EAS forever"
UPDATE contract_version
SET    tx_to = @sim_now
WHERE  player_id = 35
  AND  club_id   = 4
  AND  tx_to     = @tx_open
  AND  valid_to  = @valid_open;

-- (b) INSERT: EAS contract ends on 1 Feb, NOR contract starts that day
INSERT INTO contract_version
  (player_id, club_id, contract_type, salary_eur, valid_from, valid_to, tx_from, tx_id)
VALUES
  (35, 4, 'PERMANENT', 420000.00, '2025-07-01', '2026-02-01',  @sim_now, @tx_id),
  (35, 1, 'PERMANENT', 500000.00, '2026-02-01', @valid_open,   @sim_now, @tx_id);

COMMIT;


-- ---------------------------------------------------------------------
-- S18 | E4 correction of a wrong date: Meyer's (57) return to SOU (6)
-- was recorded in S16 as 1 Feb; it was actually 10 Feb.
-- Recorded 2026-02-20.
-- Pattern: CLOSE + INSERT with the corrected valid_from.
-- The WHERE uses valid_to = @valid_open so it picks the S16 row,
-- not his older, already-ended SOU contract from S10.
-- ---------------------------------------------------------------------
START TRANSACTION;

SET @sim_now = '2026-02-20 12:00:00';

INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'clerk_ana', 'S18 | E4 correction: Meyer returned to SOU on 10 Feb, not 1 Feb');
SET @tx_id = LAST_INSERT_ID();

-- (a) CLOSE the wrong belief "back from 1 Feb"
UPDATE contract_version
SET    tx_to = @sim_now
WHERE  player_id = 57
  AND  club_id   = 6
  AND  tx_to     = @tx_open
  AND  valid_to  = @valid_open;

-- (b) INSERT the corrected belief "back from 10 Feb"
INSERT INTO contract_version
  (player_id, club_id, contract_type, salary_eur, valid_from, tx_from, tx_id)
VALUES
  (57, 6, 'PERMANENT', 300000.00, '2026-02-10', @sim_now, @tx_id);

COMMIT;


-- ---------------------------------------------------------------------
-- S19 | E3 late entry + E7 role change (THREE-ANSWERS CASE, part 1):
-- A clerk records that HAR (3) sacked Luca Romano (3) and that
-- Sam Kelly (8) took over on 2026-03-02.
-- Recorded 2026-03-16: 14 days late.
-- Pattern: CLOSE + INSERT (split into old holder + new holder)
-- ---------------------------------------------------------------------
START TRANSACTION;

SET @sim_now = '2026-03-16 10:00:00';

INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'clerk_bob', 'S19 | E3+E7: HAR sacks Romano, Kelly head coach from 2 Mar (recorded 14 days late)');
SET @tx_id = LAST_INSERT_ID();

-- (a) CLOSE: stop believing "Romano coaches HAR forever"
UPDATE head_coach_version
SET    tx_to = @sim_now
WHERE  club_id  = 3
  AND  tx_to    = @tx_open
  AND  valid_to = @valid_open;

-- (b) INSERT: Romano until 2 Mar, Kelly from 2 Mar
INSERT INTO head_coach_version
  (club_id, coach_id, valid_from, valid_to, tx_from, tx_id)
VALUES
  (3, 3, '2025-07-01', '2026-03-02',  @sim_now, @tx_id),
  (3, 8, '2026-03-02', @valid_open,   @sim_now, @tx_id);

COMMIT;


-- ---------------------------------------------------------------------
-- S20 | E4 correction + E7 (THREE-ANSWERS CASE, part 2):
-- The sacking date is disputed; the real handover was 2026-03-06.
-- Recorded 2026-03-23.
-- Pattern: CLOSE + INSERT. BOTH current HAR rows from S19 are wrong
-- (Romano's end date and Kelly's start date), so both are closed
-- and both are re-inserted with the corrected date.
-- ---------------------------------------------------------------------
START TRANSACTION;

SET @sim_now = '2026-03-23 15:00:00';

INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'clerk_ana', 'S20 | E4+E7 correction: HAR handover Romano->Kelly was on 6 Mar, not 2 Mar');
SET @tx_id = LAST_INSERT_ID();

-- (a) CLOSE both current HAR beliefs written by S19
UPDATE head_coach_version
SET    tx_to = @sim_now
WHERE  club_id = 3
  AND  tx_to   = @tx_open;

-- (b) INSERT the corrected beliefs
INSERT INTO head_coach_version
  (club_id, coach_id, valid_from, valid_to, tx_from, tx_id)
VALUES
  (3, 3, '2025-07-01', '2026-03-06',  @sim_now, @tx_id),
  (3, 8, '2026-03-06', @valid_open,   @sim_now, @tx_id);

COMMIT;


-- ---------------------------------------------------------------------
-- S21 | E7 role change + E9 multi-table: takeover at WES (5).
-- From 2026-04-01 the new owner raises the budget (6,200,000 -> 9,000,000)
-- and replaces Daniel Ortiz (5) with Paul Weber (2).
-- Recorded 2026-04-02 (1 day later - not a late entry).
-- Patterns: CLOSE + INSERT on club_version AND on head_coach_version,
-- all with the same tx_id.
-- ---------------------------------------------------------------------
START TRANSACTION;

SET @sim_now = '2026-04-02 09:00:00';

INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'league_office', 'S21 | E7+E9: WES takeover - budget raised, Weber replaces Ortiz from 1 Apr');
SET @tx_id = LAST_INSERT_ID();

-- Table 1: club_version. Current open row is the spring budget from S12.
UPDATE club_version
SET    tx_to = @sim_now
WHERE  club_id  = 5
  AND  tx_to    = @tx_open
  AND  valid_to = @valid_open;

INSERT INTO club_version
  (club_id, name, budget_eur, valid_from, valid_to, tx_from, tx_id)
VALUES
  (5, 'Westbrook Athletic', 6200000.00, '2026-01-01', '2026-04-01', @sim_now, @tx_id),
  (5, 'Westbrook Athletic', 9000000.00, '2026-04-01', @valid_open,  @sim_now, @tx_id);

-- Table 2: head_coach_version
UPDATE head_coach_version
SET    tx_to = @sim_now
WHERE  club_id  = 5
  AND  tx_to    = @tx_open
  AND  valid_to = @valid_open;

INSERT INTO head_coach_version
  (club_id, coach_id, valid_from, valid_to, tx_from, tx_id)
VALUES
  (5, 5, '2025-07-01', '2026-04-01',  @sim_now, @tx_id),
  (5, 2, '2026-04-01', @valid_open,   @sim_now, @tx_id);

COMMIT;


-- ---------------------------------------------------------------------
-- S22 | E3 late entry: Lucas Moreau's (13) raise at RIV (2),
-- 640,000 -> 720,000 from 2026-03-01. Recorded 2026-04-10: 40 days late.
-- Pattern: CLOSE + INSERT (split at 1 Mar)
-- ---------------------------------------------------------------------
START TRANSACTION;

SET @sim_now = '2026-04-10 10:00:00';

INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'clerk_bob', 'S22 | E3: Moreau raise at RIV from 1 Mar, recorded 40 days late');
SET @tx_id = LAST_INSERT_ID();

UPDATE contract_version
SET    tx_to = @sim_now
WHERE  player_id = 13
  AND  club_id   = 2
  AND  tx_to     = @tx_open
  AND  valid_to  = @valid_open;

INSERT INTO contract_version
  (player_id, club_id, contract_type, salary_eur, valid_from, valid_to, tx_from, tx_id)
VALUES
  (13, 2, 'PERMANENT', 640000.00, '2025-07-01', '2026-03-01',  @sim_now, @tx_id),
  (13, 2, 'PERMANENT', 720000.00, '2026-03-01', @valid_open,   @sim_now, @tx_id);

COMMIT;


-- ---------------------------------------------------------------------
-- S23 | E2 proactive + E5 end: Moreau (13) pre-signs with NOR (1)
-- from 2026-07-01; his RIV (2) contract therefore ends on 30 June
-- (valid_to = 2026-07-01). Recorded 2026-05-20, six weeks ahead.
-- Pattern: CLOSE + INSERT (same shape as a transfer, but in the future)
-- ---------------------------------------------------------------------
START TRANSACTION;

SET @sim_now = '2026-05-20 12:00:00';

INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'clerk_ana', 'S23 | E2+E5: Moreau pre-signs with NOR from 1 Jul, RIV contract ends 30 Jun');
SET @tx_id = LAST_INSERT_ID();

-- (a) CLOSE the open-ended RIV row written by S22 (720,000 from 1 Mar)
UPDATE contract_version
SET    tx_to = @sim_now
WHERE  player_id = 13
  AND  club_id   = 2
  AND  tx_to     = @tx_open
  AND  valid_to  = @valid_open;

-- (b) INSERT: RIV contract now ends on 1 Jul, NOR contract starts that day
INSERT INTO contract_version
  (player_id, club_id, contract_type, salary_eur, valid_from, valid_to, tx_from, tx_id)
VALUES
  (13, 2, 'PERMANENT', 720000.00, '2026-03-01', '2026-07-01',  @sim_now, @tx_id),
  (13, 1, 'PERMANENT', 800000.00, '2026-07-01', @valid_open,   @sim_now, @tx_id);

COMMIT;