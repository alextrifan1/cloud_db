-- 03_timeline.sql
-- Every change after go-live (S2-S23), in the order it was recorded.

USE football_bt;
SET time_zone = '+00:00';


SET @valid_open = '9999-12-31';
SET @tx_open = '9999-12-31 23:59:59.999999';


-- ---------------------------------------------------------------------
-- S2 | E2: Martin (67) signs for HAR (3).
-- Recorded 10 Jul, starts 15 Jul.
-- ---------------------------------------------------------------------
START TRANSACTION;

SET @sim_now = '2025-07-10 10:00:00';

INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'clerk_ana', 'S2 | E2 proactive: Martin signs for HAR from 15 Jul');
SET @tx_id = LAST_INSERT_ID();

INSERT INTO contract_version
(player_id, club_id, contract_type, salary_eur, valid_from, tx_from, tx_id)
VALUES (67, 3, 'PERMANENT', 330000.00, '2025-07-15', @sim_now, @tx_id);

COMMIT;


-- ---------------------------------------------------------------------
-- S3 | E5: Cole (23) leaves HAR (3).
-- Last day 3 Aug (so valid_to = 4 Aug). Recorded 5 Aug.
-- ---------------------------------------------------------------------
START TRANSACTION;

SET @sim_now = '2025-08-05 11:00:00';

INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'clerk_ana', 'S3 | E5 end: Cole leaves HAR, contract terminated by mutual consent');
SET @tx_id = LAST_INSERT_ID();

-- Close the open-ended contract.
UPDATE contract_version
SET tx_to = @sim_now
WHERE player_id = 23
  AND club_id = 3
  AND tx_to = @tx_open -- still believed
  AND valid_to = @valid_open;
-- no end date yet

-- Same contract, now with an end date.
INSERT INTO contract_version
(player_id, club_id, contract_type, salary_eur, valid_from, valid_to, tx_from, tx_id)
VALUES (23, 3, 'PERMANENT', 490000.00, '2025-07-01', '2025-08-04', @sim_now, @tx_id);

COMMIT;


-- ---------------------------------------------------------------------
-- S4 | E2 + E9: Fischer (34) loaned EAS -> SOU from 25 Aug to 1 Jul 2026.
-- Same change: SOU pays a 300,000 fee, budget 5.8M -> 5.5M from 25 Aug.
-- Recorded 20 Aug. His EAS contract keeps running.
-- ---------------------------------------------------------------------
START TRANSACTION;

SET @sim_now = '2025-08-20 12:00:00';

INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'clerk_ana', 'S4 | E2+E9: Fischer loaned EAS->SOU from 25 Aug; SOU pays loan fee');
SET @tx_id = LAST_INSERT_ID();

-- Table 1: the loan.
INSERT INTO contract_version
(player_id, club_id, contract_type, salary_eur, valid_from, valid_to, tx_from, tx_id)
VALUES (34, 6, 'LOAN', 250000.00, '2025-08-25', '2026-07-01', @sim_now, @tx_id);

-- Table 2: SOU's budget. Close the open row...
UPDATE club_version
SET tx_to = @sim_now
WHERE club_id = 6
  AND tx_to = @tx_open
  AND valid_to = @valid_open;

-- ...and split it at 25 Aug: old budget before, new budget after.
INSERT INTO club_version
    (club_id, name, budget_eur, valid_from, valid_to, tx_from, tx_id)
VALUES (6, 'Southport Town', 5800000.00, '2025-07-01', '2025-08-25', @sim_now, @tx_id),
       (6, 'Southport Town', 5500000.00, '2025-08-25', @valid_open, @sim_now, @tx_id);

COMMIT;


-- ---------------------------------------------------------------------
-- S5 | E3 + E5: Hughes (12) moves RIV -> WES on 1 Sep (deadline day).
-- Recorded 12 Sep: 11 days late, after the window closed.
-- ---------------------------------------------------------------------
START TRANSACTION;

SET @sim_now = '2025-09-12 09:30:00';

INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'clerk_ana', 'S5 | E3+E5: Hughes RIV->WES on 1 Sep, registered after the window closed');
SET @tx_id = LAST_INSERT_ID();

-- Close the open RIV contract.
UPDATE contract_version
SET tx_to = @sim_now
WHERE player_id = 12
  AND club_id = 2
  AND tx_to = @tx_open
  AND valid_to = @valid_open;

-- RIV contract ends 1 Sep, WES contract starts 1 Sep.
INSERT INTO contract_version
(player_id, club_id, contract_type, salary_eur, valid_from, valid_to, tx_from, tx_id)
VALUES (12, 2, 'PERMANENT', 560000.00, '2025-07-01', '2025-09-01', @sim_now, @tx_id),
       (12, 5, 'PERMANENT', 600000.00, '2025-09-01', @valid_open, @sim_now, @tx_id);

COMMIT;


-- ---------------------------------------------------------------------
-- S6 | Setup for E8: a clerk enters a loan of Rossi (56) to NOR (1)
-- by mistake. It never happened. S7 removes it the same day.
-- ---------------------------------------------------------------------
START TRANSACTION;

SET @sim_now = '2025-09-15 08:00:00';

INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'clerk_bob', 'S6 | Rossi loaned SOU->NOR from 15 Sep (entered by mistake)');
SET @tx_id = LAST_INSERT_ID();

INSERT INTO contract_version
(player_id, club_id, contract_type, salary_eur, valid_from, valid_to, tx_from, tx_id)
VALUES (56, 1, 'LOAN', 300000.00, '2025-09-15', '2026-07-01', @sim_now, @tx_id);

COMMIT;


-- ---------------------------------------------------------------------
-- S7 | E8: retract the S6 loan.
-- Close only, no new row. valid_to is not touched: we are not saying
-- the loan ended, we are saying it never existed.
-- ---------------------------------------------------------------------
START TRANSACTION;

SET @sim_now = '2025-09-15 16:30:00';

INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'clerk_ana', 'S7 | E8 retraction: Rossi loan to NOR was never agreed, entered by mistake in S6');
SET @tx_id = LAST_INSERT_ID();

UPDATE contract_version
SET tx_to = @sim_now
WHERE player_id = 56
  AND club_id = 1
  AND tx_to = @tx_open;

COMMIT;


-- ---------------------------------------------------------------------
-- S8 | E7: RIV (2) sacks Weber (2), Larsen (7) takes over on 6 Oct.
-- Recorded the same evening.
-- ---------------------------------------------------------------------
START TRANSACTION;

SET @sim_now = '2025-10-06 18:00:00';

INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'clerk_ana', 'S8 | E7: RIV sacks Weber, Larsen head coach from 6 Oct');
SET @tx_id = LAST_INSERT_ID();

-- Close Weber's open row.
UPDATE head_coach_version
SET tx_to = @sim_now
WHERE club_id = 2
  AND tx_to = @tx_open
  AND valid_to = @valid_open;

-- Weber until 6 Oct, Larsen from 6 Oct. No gap, no overlap.
INSERT INTO head_coach_version
    (club_id, coach_id, valid_from, valid_to, tx_from, tx_id)
VALUES (2, 2, '2025-07-01', '2025-10-06', @sim_now, @tx_id),
       (2, 7, '2025-10-06', @valid_open, @sim_now, @tx_id);

COMMIT;


-- ---------------------------------------------------------------------
-- S9 | E4: Kowalski's (45) salary was typed 450,000 at go-live.
-- The right value is 540,000, from day one. Recorded 20 Oct.
-- A correction keeps the same valid period, only the value changes.
-- ---------------------------------------------------------------------
START TRANSACTION;

SET @sim_now = '2025-10-20 10:00:00';

INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'clerk_ana', 'S9 | E4 correction: Kowalski salary typo 450,000 -> 540,000');
SET @tx_id = LAST_INSERT_ID();

-- Close the wrong row.
UPDATE contract_version
SET tx_to = @sim_now
WHERE player_id = 45
  AND club_id = 5
  AND tx_to = @tx_open
  AND valid_to = @valid_open;

-- Same period, right salary.
INSERT INTO contract_version
(player_id, club_id, contract_type, salary_eur, valid_from, valid_to, tx_from, tx_id)
VALUES (45, 5, 'PERMANENT', 540000.00, '2025-07-01', @valid_open, @sim_now, @tx_id);

COMMIT;


-- ---------------------------------------------------------------------
-- S10 | E5: SOU (6) releases Meyer (57), gone from 30 Nov.
-- Recorded the same day.
-- ---------------------------------------------------------------------
START TRANSACTION;

SET @sim_now = '2025-11-30 17:00:00';

INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'clerk_ana', 'S10 | E5 end: SOU releases Meyer');
SET @tx_id = LAST_INSERT_ID();

UPDATE contract_version
SET tx_to = @sim_now
WHERE player_id = 57
  AND club_id = 6
  AND tx_to = @tx_open
  AND valid_to = @valid_open;

INSERT INTO contract_version
(player_id, club_id, contract_type, salary_eur, valid_from, valid_to, tx_from, tx_id)
VALUES (57, 6, 'PERMANENT', 350000.00, '2025-07-01', '2025-11-30', @sim_now, @tx_id);

COMMIT;


-- ---------------------------------------------------------------------
-- S11 | E2: raises for 8 NOR (1) players (ids 1-8) from 1 Jan 2026.
-- Recorded 15 Dec.
-- Many rows at once: a temporary list says who gets what, then three
-- statements close, re-insert the old salary, and insert the new one.
-- ---------------------------------------------------------------------
START TRANSACTION;

SET @sim_now = '2025-12-15 10:00:00';

INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'clerk_ana', 'S11 | E2 proactive: salary raises for 8 NOR players from 1 Jan');
SET @tx_id = LAST_INSERT_ID();

-- Who gets what. Only this session sees the table.
DROP TEMPORARY TABLE IF EXISTS tmp_raise;
CREATE TEMPORARY TABLE tmp_raise
(
    player_id  INT            NOT NULL PRIMARY KEY,
    new_salary DECIMAL(12, 2) NOT NULL
);
INSERT INTO tmp_raise (player_id, new_salary)
VALUES (1, 950000.00),
       (2, 680000.00),
       (3, 460000.00),
       (4, 580000.00),
       (5, 420000.00),
       (6, 790000.00),
       (7, 340000.00),
       (8, 520000.00);

-- 1. Close each listed player's open contract.
UPDATE contract_version AS cv
    JOIN tmp_raise AS r ON r.player_id = cv.player_id
SET cv.tx_to = @sim_now
WHERE cv.club_id = 1
  AND cv.tx_to = @tx_open
  AND cv.valid_to = @valid_open;

-- 2. Old salary, now ending 1 Jan.
--    Rows closed in step 1 are the ones with tx_to = @sim_now.
INSERT INTO contract_version
(player_id, club_id, contract_type, salary_eur, valid_from, valid_to, tx_from, tx_id)
SELECT cv.player_id,
       cv.club_id,
       cv.contract_type,
       cv.salary_eur,
       cv.valid_from,
       '2026-01-01',
       @sim_now,
       @tx_id
FROM contract_version AS cv
         JOIN tmp_raise AS r ON r.player_id = cv.player_id
WHERE cv.club_id = 1
  AND cv.tx_to = @sim_now;

-- 3. New salary, from 1 Jan, no end date.
INSERT INTO contract_version
(player_id, club_id, contract_type, salary_eur, valid_from, valid_to, tx_from, tx_id)
SELECT cv.player_id,
       cv.club_id,
       cv.contract_type,
       r.new_salary,
       '2026-01-01',
       @valid_open,
       @sim_now,
       @tx_id
FROM contract_version AS cv
         JOIN tmp_raise AS r ON r.player_id = cv.player_id
WHERE cv.club_id = 1
  AND cv.tx_to = @sim_now;

DROP TEMPORARY TABLE tmp_raise;

COMMIT;


-- ---------------------------------------------------------------------
-- S12 | E2: spring budgets for all 6 clubs from 1 Jan 2026.
-- Recorded 20 Dec. Same three steps as S11.
-- SOU's open row starts 25 Aug (from S4); copying valid_from keeps it right.
-- ---------------------------------------------------------------------
START TRANSACTION;

SET @sim_now = '2025-12-20 10:00:00';

INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'league_office', 'S12 | E2 proactive: spring budgets for all clubs from 1 Jan');
SET @tx_id = LAST_INSERT_ID();

DROP TEMPORARY TABLE IF EXISTS tmp_budget;
CREATE TEMPORARY TABLE tmp_budget
(
    club_id    INT            NOT NULL PRIMARY KEY,
    new_budget DECIMAL(14, 2) NOT NULL
);
INSERT INTO tmp_budget (club_id, new_budget)
VALUES (1, 11000000.00),
       (2, 9000000.00),
       (3, 8400000.00),
       (4, 7500000.00),
       (5, 6200000.00),
       (6, 5600000.00);

-- 1. Close each club's open row.
UPDATE club_version AS cv
    JOIN tmp_budget AS b ON b.club_id = cv.club_id
SET cv.tx_to = @sim_now
WHERE cv.tx_to = @tx_open
  AND cv.valid_to = @valid_open;

-- 2. Autumn budget, now ending 1 Jan.
INSERT INTO club_version
    (club_id, name, budget_eur, valid_from, valid_to, tx_from, tx_id)
SELECT cv.club_id,
       cv.name,
       cv.budget_eur,
       cv.valid_from,
       '2026-01-01',
       @sim_now,
       @tx_id
FROM club_version AS cv
WHERE cv.tx_to = @sim_now;

-- 3. Spring budget, from 1 Jan, no end date.
INSERT INTO club_version
    (club_id, name, budget_eur, valid_from, valid_to, tx_from, tx_id)
SELECT cv.club_id,
       cv.name,
       b.new_budget,
       '2026-01-01',
       @valid_open,
       @sim_now,
       @tx_id
FROM club_version AS cv
         JOIN tmp_budget AS b ON b.club_id = cv.club_id
WHERE cv.tx_to = @sim_now;

DROP TEMPORARY TABLE tmp_budget;

COMMIT;


-- ---------------------------------------------------------------------
-- S13 | E5: Fischer's (34) loan at SOU (6) is cut short.
-- Planned end 1 Jul 2026, real end 15 Jan. Recorded 16 Jan.
-- His EAS contract keeps running.
-- ---------------------------------------------------------------------
START TRANSACTION;

SET @sim_now = '2026-01-16 09:00:00';

INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'clerk_ana', 'S13 | E5 end: Fischer loan at SOU cut short, ends 15 Jan');
SET @tx_id = LAST_INSERT_ID();

UPDATE contract_version
SET tx_to = @sim_now
WHERE player_id = 34
  AND club_id = 6
  AND tx_to = @tx_open; -- only one current row here: the loan

INSERT INTO contract_version
(player_id, club_id, contract_type, salary_eur, valid_from, valid_to, tx_from, tx_id)
VALUES (34, 6, 'LOAN', 250000.00, '2025-08-25', '2026-01-15', @sim_now, @tx_id);

COMMIT;


-- ---------------------------------------------------------------------
-- S14 | E2 + E6: Hughes (12) back at RIV (2), on loan from WES.
-- 20 Jan to 1 Jul 2026, recorded 19 Jan.
-- He was at RIV until 1 Sep (S5), so this is a restart after a gap.
-- ---------------------------------------------------------------------
START TRANSACTION;

SET @sim_now = '2026-01-19 14:00:00';

INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'clerk_ana', 'S14 | E2+E6: Hughes back at RIV on loan from WES, from 20 Jan');
SET @tx_id = LAST_INSERT_ID();

INSERT INTO contract_version
(player_id, club_id, contract_type, salary_eur, valid_from, valid_to, tx_from, tx_id)
VALUES (12, 2, 'LOAN', 280000.00, '2026-01-20', '2026-07-01', @sim_now, @tx_id);

COMMIT;


-- ---------------------------------------------------------------------
-- S15 | E3 + E6: Cole (23) rejoins HAR (3) from 10 Jan.
-- Recorded 20 Jan: 10 days late. He left on 4 Aug (S3).
-- ---------------------------------------------------------------------
START TRANSACTION;

SET @sim_now = '2026-01-20 11:00:00';

INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'clerk_ana', 'S15 | E3+E6: Cole rejoins HAR from 10 Jan, recorded 10 days late');
SET @tx_id = LAST_INSERT_ID();

INSERT INTO contract_version
(player_id, club_id, contract_type, salary_eur, valid_from, tx_from, tx_id)
VALUES (23, 3, 'PERMANENT', 420000.00, '2026-01-10', @sim_now, @tx_id);

COMMIT;


-- ---------------------------------------------------------------------
-- S16 | E2 + E6: Meyer (57) rejoins SOU (6) from 1 Feb.
-- Recorded 28 Jan. He left on 30 Nov (S10).
-- The date is wrong; S18 fixes it.
-- ---------------------------------------------------------------------
START TRANSACTION;

SET @sim_now = '2026-01-28 15:00:00';

INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'clerk_ana', 'S16 | E2+E6: Meyer rejoins SOU from 1 Feb');
SET @tx_id = LAST_INSERT_ID();

INSERT INTO contract_version
(player_id, club_id, contract_type, salary_eur, valid_from, tx_from, tx_id)
VALUES (57, 6, 'PERMANENT', 300000.00, '2026-02-01', @sim_now, @tx_id);

COMMIT;


-- ---------------------------------------------------------------------
-- S17 | E3 + E5: Baker (35) moves EAS -> NOR on 1 Feb (deadline day).
-- Recorded 11 Feb: 10 days late, after the winter window closed.
-- ---------------------------------------------------------------------
START TRANSACTION;

SET @sim_now = '2026-02-11 10:00:00';

INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'clerk_ana', 'S17 | E3+E5: Baker EAS->NOR on 1 Feb, registered after the winter window');
SET @tx_id = LAST_INSERT_ID();

-- Close the open EAS contract.
UPDATE contract_version
SET tx_to = @sim_now
WHERE player_id = 35
  AND club_id = 4
  AND tx_to = @tx_open
  AND valid_to = @valid_open;

-- EAS contract ends 1 Feb, NOR contract starts 1 Feb.
INSERT INTO contract_version
(player_id, club_id, contract_type, salary_eur, valid_from, valid_to, tx_from, tx_id)
VALUES (35, 4, 'PERMANENT', 420000.00, '2025-07-01', '2026-02-01', @sim_now, @tx_id),
       (35, 1, 'PERMANENT', 500000.00, '2026-02-01', @valid_open, @sim_now, @tx_id);

COMMIT;


-- ---------------------------------------------------------------------
-- S18 | E4: Meyer (57) came back to SOU (6) on 10 Feb, not 1 Feb.
-- Recorded 20 Feb.
-- He has two current SOU rows; valid_to = open picks the S16 one,
-- not his old contract that ended 30 Nov.
-- ---------------------------------------------------------------------
START TRANSACTION;

SET @sim_now = '2026-02-20 12:00:00';

INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'clerk_ana', 'S18 | E4 correction: Meyer returned to SOU on 10 Feb, not 1 Feb');
SET @tx_id = LAST_INSERT_ID();

-- Close the wrong row.
UPDATE contract_version
SET tx_to = @sim_now
WHERE player_id = 57
  AND club_id = 6
  AND tx_to = @tx_open
  AND valid_to = @valid_open;

-- Same contract, right start date.
INSERT INTO contract_version
(player_id, club_id, contract_type, salary_eur, valid_from, tx_from, tx_id)
VALUES (57, 6, 'PERMANENT', 300000.00, '2026-02-10', @sim_now, @tx_id);

COMMIT;


-- ---------------------------------------------------------------------
-- S19 | E3 + E7: HAR (3) sacks Romano (3), Kelly (8) takes over 2 Mar.
-- Recorded 16 Mar: 14 days late.
-- Three-answers case, part 1.
-- ---------------------------------------------------------------------
START TRANSACTION;

SET @sim_now = '2026-03-16 10:00:00';

INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'clerk_bob', 'S19 | E3+E7: HAR sacks Romano, Kelly head coach from 2 Mar (recorded 14 days late)');
SET @tx_id = LAST_INSERT_ID();

-- Close Romano's open row.
UPDATE head_coach_version
SET tx_to = @sim_now
WHERE club_id = 3
  AND tx_to = @tx_open
  AND valid_to = @valid_open;

-- Romano until 2 Mar, Kelly from 2 Mar.
INSERT INTO head_coach_version
    (club_id, coach_id, valid_from, valid_to, tx_from, tx_id)
VALUES (3, 3, '2025-07-01', '2026-03-02', @sim_now, @tx_id),
       (3, 8, '2026-03-02', @valid_open, @sim_now, @tx_id);

COMMIT;


-- ---------------------------------------------------------------------
-- S20 | E4 + E7: the handover was really on 6 Mar, not 2 Mar.
-- Recorded 23 Mar. Three-answers case, part 2.
-- Both S19 rows have the wrong date, so both are closed and redone.
-- ---------------------------------------------------------------------
START TRANSACTION;

SET @sim_now = '2026-03-23 15:00:00';

INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'clerk_ana', 'S20 | E4+E7 correction: HAR handover Romano->Kelly was on 6 Mar, not 2 Mar');
SET @tx_id = LAST_INSERT_ID();

-- Close both current HAR rows.
UPDATE head_coach_version
SET tx_to = @sim_now
WHERE club_id = 3
  AND tx_to = @tx_open;

-- Romano until 6 Mar, Kelly from 6 Mar.
INSERT INTO head_coach_version
    (club_id, coach_id, valid_from, valid_to, tx_from, tx_id)
VALUES (3, 3, '2025-07-01', '2026-03-06', @sim_now, @tx_id),
       (3, 8, '2026-03-06', @valid_open, @sim_now, @tx_id);

COMMIT;


-- ---------------------------------------------------------------------
-- S21 | E7 + E9: takeover at WES (5) from 1 Apr.
-- Budget 6.2M -> 9.0M and Weber (2) replaces Ortiz (5).
-- Recorded 2 Apr (1 day later, so not a late entry).
-- Two tables, one tx_id.
-- ---------------------------------------------------------------------
START TRANSACTION;

SET @sim_now = '2026-04-02 09:00:00';

INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'league_office', 'S21 | E7+E9: WES takeover - budget raised, Weber replaces Ortiz from 1 Apr');
SET @tx_id = LAST_INSERT_ID();

-- Table 1: budget. The open row is the spring budget from S12.
UPDATE club_version
SET tx_to = @sim_now
WHERE club_id = 5
  AND tx_to = @tx_open
  AND valid_to = @valid_open;

INSERT INTO club_version
    (club_id, name, budget_eur, valid_from, valid_to, tx_from, tx_id)
VALUES (5, 'Westbrook Athletic', 6200000.00, '2026-01-01', '2026-04-01', @sim_now, @tx_id),
       (5, 'Westbrook Athletic', 9000000.00, '2026-04-01', @valid_open, @sim_now, @tx_id);

-- Table 2: head coach.
UPDATE head_coach_version
SET tx_to = @sim_now
WHERE club_id = 5
  AND tx_to = @tx_open
  AND valid_to = @valid_open;

INSERT INTO head_coach_version
    (club_id, coach_id, valid_from, valid_to, tx_from, tx_id)
VALUES (5, 5, '2025-07-01', '2026-04-01', @sim_now, @tx_id),
       (5, 2, '2026-04-01', @valid_open, @sim_now, @tx_id);

COMMIT;


-- ---------------------------------------------------------------------
-- S22 | E3: Moreau (13) gets a raise at RIV (2), 640k -> 720k from 1 Mar.
-- Recorded 10 Apr: 40 days late.
-- ---------------------------------------------------------------------
START TRANSACTION;

SET @sim_now = '2026-04-10 10:00:00';

INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'clerk_bob', 'S22 | E3: Moreau raise at RIV from 1 Mar, recorded 40 days late');
SET @tx_id = LAST_INSERT_ID();

UPDATE contract_version
SET tx_to = @sim_now
WHERE player_id = 13
  AND club_id = 2
  AND tx_to = @tx_open
  AND valid_to = @valid_open;

-- Old salary until 1 Mar, new salary from 1 Mar.
INSERT INTO contract_version
(player_id, club_id, contract_type, salary_eur, valid_from, valid_to, tx_from, tx_id)
VALUES (13, 2, 'PERMANENT', 640000.00, '2025-07-01', '2026-03-01', @sim_now, @tx_id),
       (13, 2, 'PERMANENT', 720000.00, '2026-03-01', @valid_open, @sim_now, @tx_id);

COMMIT;


-- ---------------------------------------------------------------------
-- S23 | E2 + E5: Moreau (13) signs with NOR (1) from 1 Jul 2026.
-- His RIV (2) contract ends 30 Jun. Recorded 20 May, six weeks ahead.
-- ---------------------------------------------------------------------
START TRANSACTION;

SET @sim_now = '2026-05-20 12:00:00';

INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'clerk_ana', 'S23 | E2+E5: Moreau pre-signs with NOR from 1 Jul, RIV contract ends 30 Jun');
SET @tx_id = LAST_INSERT_ID();

-- Close the open RIV row from S22.
UPDATE contract_version
SET tx_to = @sim_now
WHERE player_id = 13
  AND club_id = 2
  AND tx_to = @tx_open
  AND valid_to = @valid_open;

-- RIV contract ends 1 Jul, NOR contract starts 1 Jul.
INSERT INTO contract_version
(player_id, club_id, contract_type, salary_eur, valid_from, valid_to, tx_from, tx_id)
VALUES (13, 2, 'PERMANENT', 720000.00, '2026-03-01', '2026-07-01', @sim_now, @tx_id),
       (13, 1, 'PERMANENT', 800000.00, '2026-07-01', @valid_open, @sim_now, @tx_id);

COMMIT;