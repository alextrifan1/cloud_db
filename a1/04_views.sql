-- =====================================================================
-- 04_views.sql
-- One view per temporal question (Q0-Q8).
-- Run after 01_schema.sql, 02_data.sql and 03_timeline.sql.
--
-- MariaDB views cannot take parameters, so every view reads its inputs
-- from the one-row table query_params. 05_tests.sql changes those
-- values with UPDATE, then selects from the views.
--
-- Note: views cannot use session variables like @tx_open, so the
-- sentinels are written out in full inside the views.
-- =====================================================================

USE football_bt;
SET time_zone = '+00:00';

-- ---------------------------------------------------------------------
-- query_params: the "input box" for all views.
-- Non-temporal: a technical helper, not domain data.
-- PRIMARY KEY + CHECK (id = 1) make a second row impossible.
-- ---------------------------------------------------------------------

DROP TABLE IF EXISTS query_params;

CREATE TABLE query_params
(
    id           TINYINT     NOT NULL DEFAULT 1,
    valid_at     DATE        NOT NULL, -- what was true on
    known_at     DATETIME(6) NOT NULL, -- as the database knew it at
    period_start DATE        NOT NULL,
    period_end   DATE        NOT NULL,
    subject_id   INT         NOT NULL,
    PRIMARY KEY (id),
    CHECK ( id = 1 ),
    CHECK ( period_start < period_end )
);

INSERT INTO query_params (id, valid_at, known_at, period_start, period_end, subject_id)
VALUES (1, '2026-03-04', '2026-03-10 00:00:00', '2025-07-01', '2026-01-01', 1);

-- ---------------------------------------------------------------------
-- Q1 | Current contracts of one player.
-- Dimension: both clocks, "now".
--   valid time:       valid today         -> valid_from <= CURDATE() < valid_to
--   transaction time: still believed now  -> tx_to = sentinel
-- Parameter: query_params.subject_id = the player_id
-- ---------------------------------------------------------------------

CREATE OR REPLACE VIEW v_q1_current_contracts AS
SELECT p.player_id,
       p.first_name,
       p.last_name,
       c.short_code AS club,
       cv.contract_type,
       cv.salary_eur,
       cv.valid_from,
       cv.valid_to
FROM contract_version AS cv
         JOIN query_params AS qp ON cv.player_id = qp.subject_id -- only the chosen player
         JOIN player AS p ON p.player_id = cv.player_id -- add his name
         JOIN club AS c ON c.club_id = cv.club_id -- add the club code
WHERE cv.valid_from <= CURDATE() -- valid today ...
  AND CURDATE() < cv.valid_to
  AND cv.tx_to = '9999-12-31 23:59:59.999999'; -- ... and still believed
