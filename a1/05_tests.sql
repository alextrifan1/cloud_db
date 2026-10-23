-- =====================================================================
-- 05_tests.sql
-- Calls every view with concrete parameters.
-- Run after 01-04. Each test: set the parameters, then read the view.
-- Expected results are written above each SELECT.
-- =====================================================================

USE football_bt;
SET time_zone = '+00:00';


-- ---------------------------------------------------------------------
-- Q1 | Current contracts of one player
-- ---------------------------------------------------------------------

-- Test Q1.a: Lucas Moreau (13)
-- Story: raise at RIV (S22), then moved to NOR from 1 Jul 2026 (S23).
-- Expect 1 row: NOR, PERMANENT, 800,000, valid from 2026-07-01
UPDATE query_params SET subject_id = 13 WHERE id = 1;
SELECT * FROM v_q1_current_contracts;

-- Test Q1.b: Sean Hughes (12)
-- Story: RIV -> WES (S5), then back at RIV on loan until 1 Jul 2026 (S14).
-- The loan has ended by today, so only his WES contract is current.
-- Expect 1 row: WES, PERMANENT, 600,000, valid from 2025-09-01
UPDATE query_params SET subject_id = 12 WHERE id = 1;
SELECT * FROM v_q1_current_contracts;

-- Test Q1.c: Nico Rossi (56)
-- Story: a loan to NOR was entered by mistake (S6) and retracted (S7).
-- The retracted loan must NOT appear.
-- Expect 1 row: SOU, PERMANENT, 400,000, valid from 2025-07-01
UPDATE query_params SET subject_id = 56 WHERE id = 1;
SELECT * FROM v_q1_current_contracts;

-- Test Q1.d: Samuel Ward (68), a free agent who never signed
-- Expect 0 rows
UPDATE query_params SET subject_id = 68 WHERE id = 1;
SELECT * FROM v_q1_current_contracts;