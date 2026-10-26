-- 04_views.sql
-- One view per question, Q0-Q8.
-- Run after 01, 02 and 03.
--
-- Views cannot take parameters, so they read their inputs from the
-- one-row table query_params. 05_tests.sql sets the values, then
-- reads the views.
-- Views cannot use @variables, so the open-end values are written out.

USE football_bt;
SET time_zone = '+00:00';


-- =====================================================================
-- query_params: the inputs for every view.
-- No history needed: it is a helper, not data about the league.
-- The PRIMARY KEY plus CHECK (id = 1) allow only one row.
-- =====================================================================
DROP TABLE IF EXISTS query_params;

CREATE TABLE query_params (
                              id            TINYINT      NOT NULL DEFAULT 1,
                              valid_at      DATE         NOT NULL,   -- "true on ..."            (Q6)
                              known_at      DATETIME(6)  NOT NULL,   -- "as the database knew at" (Q5, Q6)
                              period_start  DATE         NOT NULL,   -- included                 (Q4)
                              period_end    DATE         NOT NULL,   -- not included             (Q4)
                              subject_id    INT          NOT NULL,   -- player_id (Q1) or club_id (Q2, Q6)
                              PRIMARY KEY (id),
                              CHECK (id = 1),
                              CHECK (period_start < period_end)
);

INSERT INTO query_params (id, valid_at, known_at, period_start, period_end, subject_id)
VALUES (1, '2026-03-04', '2026-03-10 00:00:00', '2025-07-01', '2026-01-01', 1);


-- =====================================================================
-- Q0 | Rows that break invariant I1, I2 or I3.
-- Only rows still believed (tx_to open) are checked.
-- Must return zero rows on the final data.
-- =====================================================================
CREATE OR REPLACE VIEW v_integrity_violations AS

-- I1: two current contracts of the same player at the same club overlap.
SELECT 'I1' AS invariant, 'contract_version' AS table_name,
       a.version_id, b.version_id AS other_version_id,
       CONCAT('player ', a.player_id, ' at club ', a.club_id, ': periods overlap') AS problem
FROM contract_version AS a
         JOIN contract_version AS b
              ON  b.player_id  = a.player_id
                  AND b.club_id    = a.club_id
                  AND b.version_id > a.version_id                  -- each pair once
                  AND a.valid_from < b.valid_to                    -- overlap
                  AND b.valid_from < a.valid_to
WHERE a.tx_to = '9999-12-31 23:59:59.999999'
  AND b.tx_to = '9999-12-31 23:59:59.999999'

UNION ALL

-- I1: two current versions of the same club overlap.
SELECT 'I1', 'club_version', a.version_id, b.version_id,
       CONCAT('club ', a.club_id, ': periods overlap')
FROM club_version AS a
         JOIN club_version AS b
              ON  b.club_id    = a.club_id
                  AND b.version_id > a.version_id
                  AND a.valid_from < b.valid_to
                  AND b.valid_from < a.valid_to
WHERE a.tx_to = '9999-12-31 23:59:59.999999'
  AND b.tx_to = '9999-12-31 23:59:59.999999'

UNION ALL

-- I1: the same coach is stored twice for the same club and time.
SELECT 'I1', 'head_coach_version', a.version_id, b.version_id,
       CONCAT('club ', a.club_id, ', coach ', a.coach_id, ': periods overlap')
FROM head_coach_version AS a
         JOIN head_coach_version AS b
              ON  b.club_id    = a.club_id
                  AND b.coach_id   = a.coach_id
                  AND b.version_id > a.version_id
                  AND a.valid_from < b.valid_to
                  AND b.valid_from < a.valid_to
WHERE a.tx_to = '9999-12-31 23:59:59.999999'
  AND b.tx_to = '9999-12-31 23:59:59.999999'

UNION ALL

-- I3: two different head coaches of one club at the same time.
SELECT 'I3', 'head_coach_version', a.version_id, b.version_id,
       CONCAT('club ', a.club_id, ': coaches ', a.coach_id, ' and ', b.coach_id, ' at the same time')
FROM head_coach_version AS a
         JOIN head_coach_version AS b
              ON  b.club_id    = a.club_id
                  AND b.coach_id  <> a.coach_id
                  AND b.version_id > a.version_id
                  AND a.valid_from < b.valid_to
                  AND b.valid_from < a.valid_to
WHERE a.tx_to = '9999-12-31 23:59:59.999999'
  AND b.tx_to = '9999-12-31 23:59:59.999999'

UNION ALL

-- I2: a contract is not fully inside the club's league membership.
-- It is covered when (1) some club version covers its first day, and
-- (2) every club version that ends inside the contract is followed
-- straight away by another one.
SELECT 'I2', 'contract_version', c.version_id, NULL,
       CONCAT('player ', c.player_id, ': contract outlives club ', c.club_id)
FROM contract_version AS c
WHERE c.tx_to = '9999-12-31 23:59:59.999999'
  AND (
    NOT EXISTS (                                  -- (1) first day not covered
        SELECT 1 FROM club_version AS p
        WHERE p.club_id = c.club_id
          AND p.tx_to   = '9999-12-31 23:59:59.999999'
          AND p.valid_from <= c.valid_from AND c.valid_from < p.valid_to)
        OR EXISTS (                                      -- (2) a hole inside the contract
        SELECT 1 FROM club_version AS p
        WHERE p.club_id = c.club_id
          AND p.tx_to   = '9999-12-31 23:59:59.999999'
          AND c.valid_from < p.valid_to AND p.valid_to < c.valid_to
          AND NOT EXISTS (
            SELECT 1 FROM club_version AS q
            WHERE q.club_id = c.club_id
              AND q.tx_to   = '9999-12-31 23:59:59.999999'
              AND q.valid_from <= p.valid_to AND p.valid_to < q.valid_to))
    )

UNION ALL

-- I2: the same check for head coach spells.
SELECT 'I2', 'head_coach_version', h.version_id, NULL,
       CONCAT('coach ', h.coach_id, ': spell outlives club ', h.club_id)
FROM head_coach_version AS h
WHERE h.tx_to = '9999-12-31 23:59:59.999999'
  AND (
    NOT EXISTS (
        SELECT 1 FROM club_version AS p
        WHERE p.club_id = h.club_id
          AND p.tx_to   = '9999-12-31 23:59:59.999999'
          AND p.valid_from <= h.valid_from AND h.valid_from < p.valid_to)
        OR EXISTS (
        SELECT 1 FROM club_version AS p
        WHERE p.club_id = h.club_id
          AND p.tx_to   = '9999-12-31 23:59:59.999999'
          AND h.valid_from < p.valid_to AND p.valid_to < h.valid_to
          AND NOT EXISTS (
            SELECT 1 FROM club_version AS q
            WHERE q.club_id = h.club_id
              AND q.tx_to   = '9999-12-31 23:59:59.999999'
              AND q.valid_from <= p.valid_to AND p.valid_to < q.valid_to))
    );


-- =====================================================================
-- Q1 | Current contracts of one player.
-- Both clocks, "now": valid today and still believed.
-- Input: subject_id = player_id
-- =====================================================================
CREATE OR REPLACE VIEW v_q1_player_contracts_now AS
SELECT
    p.player_id,
    p.first_name,
    p.last_name,
    c.short_code      AS club,
    cv.contract_type,
    cv.salary_eur,
    cv.valid_from,
    cv.valid_to
FROM contract_version AS cv
         JOIN query_params     AS qp ON cv.player_id = qp.subject_id      -- the chosen player
         JOIN player           AS p  ON p.player_id  = cv.player_id
         JOIN club             AS c  ON c.club_id    = cv.club_id
WHERE cv.valid_from <= CURDATE()                                  -- valid today
  AND CURDATE()     <  cv.valid_to
  AND cv.tx_to       = '9999-12-31 23:59:59.999999';              -- still believed


-- =====================================================================
-- Q2 | Head coaches of one club, as known today, one row per tenure.
-- Valid time. Rows next to each other with the same coach are merged
-- ("gaps and islands"):
--   1. mark a row as a new tenure unless it continues the row before
--      (same coach, starts the day the previous one ended)
--   2. a running sum of those marks numbers the tenures
--   3. group by that number
-- Input: subject_id = club_id
-- =====================================================================
CREATE OR REPLACE VIEW v_q2_head_coach_history AS
WITH cur AS (
    SELECT
        hc.club_id, hc.coach_id, hc.valid_from, hc.valid_to,
        CASE
            WHEN LAG(hc.coach_id) OVER (PARTITION BY hc.club_id ORDER BY hc.valid_from) = hc.coach_id
                AND LAG(hc.valid_to) OVER (PARTITION BY hc.club_id ORDER BY hc.valid_from) = hc.valid_from
                THEN 0 ELSE 1
            END AS is_new_tenure
    FROM head_coach_version AS hc
             JOIN query_params       AS qp ON hc.club_id = qp.subject_id
    WHERE hc.tx_to = '9999-12-31 23:59:59.999999'                   -- as known today
),
     numbered AS (
         SELECT cur.*,
                SUM(is_new_tenure) OVER (PARTITION BY club_id ORDER BY valid_from) AS tenure_no
         FROM cur
     )
SELECT
    cl.short_code                        AS club,
    n.tenure_no,
    co.first_name,
    co.last_name,
    MIN(n.valid_from)                    AS tenure_start,
    MAX(n.valid_to)                      AS tenure_end,
    COUNT(*)                             AS rows_merged,
    -- ongoing tenures are measured up to today
    DATEDIFF(LEAST(MAX(n.valid_to), CURDATE()), MIN(n.valid_from)) AS tenure_days,
    CASE WHEN MAX(n.valid_to) = '9999-12-31' THEN 'yes' ELSE 'no' END AS still_in_charge
FROM numbered AS n
         JOIN coach    AS co ON co.coach_id = n.coach_id
         JOIN club     AS cl ON cl.club_id  = n.club_id
GROUP BY n.club_id, n.tenure_no, n.coach_id, cl.short_code, co.first_name, co.last_name;


-- =====================================================================
-- Q3 | Late entries (E3), proactive entries (E2) and corrections (E4),
-- with the delay in days and the old and new belief side by side.
-- Transaction time vs valid time.
--
-- A change re-writes unchanged history too, so single rows cannot be
-- judged alone. For every change and every key it touched we compare
-- the old belief (rows it closed) with the new belief (rows it wrote),
-- and find the first valid date where they differ: the change date.
--   no new rows                      -> RETRACTION (E8)
--   an old row starts on that date   -> CORRECTION (E4): a stated fact was wrong
--   change date after recording day  -> PROACTIVE  (E2)
--   recorded 7 or more days later    -> LATE       (E3)
--   anything else                    -> on time, not listed
-- =====================================================================
CREATE OR REPLACE VIEW v_q3_late_proactive_corrections AS
WITH
-- All three history tables in one shape: table, key, text value, periods.
v AS (
    SELECT 'contract' AS tbl, cv.player_id AS k1, cv.club_id AS k2,
           CONCAT(p.first_name, ' ', p.last_name, ' at ', c.short_code) AS subject,
           CONCAT(cv.contract_type, ' ', cv.salary_eur) AS val,
           cv.valid_from, cv.valid_to, cv.tx_from, cv.tx_to
    FROM contract_version AS cv
             JOIN player AS p ON p.player_id = cv.player_id
             JOIN club   AS c ON c.club_id   = cv.club_id
    UNION ALL
    SELECT 'head_coach', hc.club_id, 0,
           CONCAT('head coach of ', c.short_code),
           CONCAT(co.first_name, ' ', co.last_name),
           hc.valid_from, hc.valid_to, hc.tx_from, hc.tx_to
    FROM head_coach_version AS hc
             JOIN coach AS co ON co.coach_id = hc.coach_id
             JOIN club  AS c  ON c.club_id   = hc.club_id
    UNION ALL
    SELECT 'club', cl.club_id, 0,
           CONCAT('club ', c.short_code),
           CONCAT(cl.name, ' budget ', cl.budget_eur),
           cl.valid_from, cl.valid_to, cl.tx_from, cl.tx_to
    FROM club_version AS cl
             JOIN club AS c ON c.club_id = cl.club_id
),
-- One row per (change, key it touched).
touched AS (
    SELECT DISTINCT t.tx_id, t.tx_time, t.reason, v.tbl, v.k1, v.k2, v.subject
    FROM tx_registry AS t
             JOIN v ON v.tx_from = t.tx_time OR v.tx_to = t.tx_time
),
-- Dates where the old or new belief can switch value.
pts AS (
    SELECT tc.tx_id, tc.tx_time, tc.tbl, tc.k1, tc.k2, v.valid_from AS d
    FROM touched AS tc
             JOIN v ON v.tbl = tc.tbl AND v.k1 = tc.k1 AND v.k2 = tc.k2
        AND (v.tx_from = tc.tx_time OR v.tx_to = tc.tx_time)
    UNION
    SELECT tc.tx_id, tc.tx_time, tc.tbl, tc.k1, tc.k2, v.valid_to
    FROM touched AS tc
             JOIN v ON v.tbl = tc.tbl AND v.k1 = tc.k1 AND v.k2 = tc.k2
        AND (v.tx_from = tc.tx_time OR v.tx_to = tc.tx_time)
    WHERE v.valid_to < '9999-12-31'
),
-- Old and new value at each of those dates.
cmp AS (
    SELECT pts.*,
           (SELECT o.val FROM v AS o
            WHERE o.tbl = pts.tbl AND o.k1 = pts.k1 AND o.k2 = pts.k2
              AND o.tx_to = pts.tx_time                              -- closed by this change
              AND o.valid_from <= pts.d AND pts.d < o.valid_to
            LIMIT 1) AS old_val,
           (SELECT n.val FROM v AS n
            WHERE n.tbl = pts.tbl AND n.k1 = pts.k1 AND n.k2 = pts.k2
              AND n.tx_from = pts.tx_time                            -- written by this change
              AND n.valid_from <= pts.d AND pts.d < n.valid_to
            LIMIT 1) AS new_val
    FROM pts
),
-- First date where they differ.
chg AS (
    SELECT tx_id, tbl, k1, k2, MIN(d) AS change_date
    FROM cmp
    WHERE NOT (old_val <=> new_val)
    GROUP BY tx_id, tbl, k1, k2
),
classified AS (
    SELECT
        SUBSTRING_INDEX(tc.reason, ' |', 1)                AS story_event,
        tc.tx_time                                         AS recorded_at,
        tc.tbl                                             AS table_name,
        tc.subject,
        ch.change_date,
        DATEDIFF(DATE(tc.tx_time), ch.change_date)         AS delay_days,
        CASE
            WHEN NOT EXISTS (SELECT 1 FROM v AS n
                             WHERE n.tbl = tc.tbl AND n.k1 = tc.k1 AND n.k2 = tc.k2
                               AND n.tx_from = tc.tx_time)
                THEN 'RETRACTION (E8)'
            WHEN EXISTS (SELECT 1 FROM v AS o
                         WHERE o.tbl = tc.tbl AND o.k1 = tc.k1 AND o.k2 = tc.k2
                           AND o.tx_to = tc.tx_time AND o.valid_from = ch.change_date)
                THEN 'CORRECTION (E4)'
            WHEN ch.change_date > DATE(tc.tx_time)
                THEN 'PROACTIVE (E2)'
            WHEN DATEDIFF(DATE(tc.tx_time), ch.change_date) >= 7
                THEN 'LATE (E3)'
            ELSE 'ON TIME'
            END                                                AS classification,
        COALESCE((SELECT GROUP_CONCAT(CONCAT(o.val, ' [', o.valid_from, ', ', o.valid_to, ')')
                                      ORDER BY o.valid_from SEPARATOR ' | ')
                  FROM v AS o
                  WHERE o.tbl = tc.tbl AND o.k1 = tc.k1 AND o.k2 = tc.k2
                    AND o.tx_to = tc.tx_time), '(nothing)') AS old_belief,
        COALESCE((SELECT GROUP_CONCAT(CONCAT(n.val, ' [', n.valid_from, ', ', n.valid_to, ')')
                                      ORDER BY n.valid_from SEPARATOR ' | ')
                  FROM v AS n
                  WHERE n.tbl = tc.tbl AND n.k1 = tc.k1 AND n.k2 = tc.k2
                    AND n.tx_from = tc.tx_time), '(nothing)') AS new_belief
    FROM touched AS tc
             JOIN chg     AS ch ON ch.tx_id = tc.tx_id AND ch.tbl = tc.tbl
        AND ch.k1 = tc.k1 AND ch.k2 = tc.k2
)
SELECT *
FROM classified
WHERE classification <> 'ON TIME';


-- =====================================================================
-- Q4 | Contracts valid during a named period, as known today.
-- Valid time. Two answers per contract:
--   at_some_point  overlap      from < period_end AND period_start < to
--   throughout     containment  from <= period_start AND period_end <= to
-- Rows next to each other for the same player, club and type are merged
-- first, so a mid-season raise does not break "throughout".
-- Input: period_start, period_end
-- =====================================================================
CREATE OR REPLACE VIEW v_q4_contracts_in_period AS
WITH cur AS (
    SELECT
        cv.player_id, cv.club_id, cv.contract_type, cv.valid_from, cv.valid_to,
        CASE
            WHEN LAG(cv.valid_to) OVER (PARTITION BY cv.player_id, cv.club_id, cv.contract_type
                ORDER BY cv.valid_from) = cv.valid_from
                THEN 0 ELSE 1
            END AS is_new_spell
    FROM contract_version AS cv
    WHERE cv.tx_to = '9999-12-31 23:59:59.999999'
),
     numbered AS (
         SELECT cur.*,
                SUM(is_new_spell) OVER (PARTITION BY player_id, club_id, contract_type
                    ORDER BY valid_from) AS spell_no
         FROM cur
     ),
     spells AS (
         SELECT player_id, club_id, contract_type,
                MIN(valid_from) AS spell_from,
                MAX(valid_to)   AS spell_to
         FROM numbered
         GROUP BY player_id, club_id, contract_type, spell_no
     )
SELECT
    qp.period_start,
    qp.period_end,
    p.first_name,
    p.last_name,
    c.short_code   AS club,
    s.contract_type,
    s.spell_from,
    s.spell_to,
    'yes'          AS at_some_point,
    CASE WHEN s.spell_from <= qp.period_start AND qp.period_end <= s.spell_to
             THEN 'yes' ELSE 'no' END AS throughout
FROM spells       AS s
         CROSS JOIN query_params AS qp
         JOIN player       AS p ON p.player_id = s.player_id
         JOIN club         AS c ON c.club_id   = s.club_id
WHERE s.spell_from  < qp.period_end                               -- overlap
  AND qp.period_start < s.spell_to;


-- =====================================================================
-- Q5 | All contracts as the database believed them at known_at.
-- Transaction time only: any valid time, past, present or future.
-- Input: known_at
-- =====================================================================
CREATE OR REPLACE VIEW v_q5_contracts_believed_at AS
SELECT
    qp.known_at,
    cv.player_id,
    p.first_name,
    p.last_name,
    c.short_code      AS club,
    cv.contract_type,
    cv.salary_eur,
    cv.valid_from,
    cv.valid_to,
    cv.tx_from,
    cv.tx_to
FROM contract_version AS cv
         JOIN query_params     AS qp ON cv.tx_from <= qp.known_at       -- already written
    AND qp.known_at < cv.tx_to          -- not yet replaced
         JOIN player           AS p  ON p.player_id = cv.player_id
         JOIN club             AS c  ON c.club_id   = cv.club_id;


-- =====================================================================
-- Q6 | One club at one moment: who was head coach and who was in the
-- squad on valid_at, as the database knew it at known_at.
-- Both clocks: the core predicate from the assignment, on two tables.
-- Changing only known_at gives the three answers for HAR on 4 March.
-- Uses ix_coach_asof and ix_contract_club_asof (club_id, tx_to, valid_from).
-- Input: subject_id = club_id, valid_at, known_at
-- =====================================================================
CREATE OR REPLACE VIEW v_q6_club_as_of AS
SELECT
    'HEAD COACH'                              AS fact,
    c.short_code                              AS club,
    CONCAT(co.first_name, ' ', co.last_name)  AS person,
    NULL                                      AS details,
    hc.valid_from, hc.valid_to, hc.tx_from, hc.tx_to
FROM head_coach_version AS hc
         CROSS JOIN query_params AS qp
         JOIN coach AS co ON co.coach_id = hc.coach_id
         JOIN club  AS c  ON c.club_id   = hc.club_id
WHERE hc.club_id    = qp.subject_id
  AND hc.valid_from <= qp.valid_at AND qp.valid_at < hc.valid_to    -- true then
  AND hc.tx_from    <= qp.known_at AND qp.known_at < hc.tx_to       -- known then

UNION ALL

SELECT
    'PLAYER',
    c.short_code,
    CONCAT(p.first_name, ' ', p.last_name),
    CONCAT(cv.contract_type, ' ', cv.salary_eur),
    cv.valid_from, cv.valid_to, cv.tx_from, cv.tx_to
FROM contract_version AS cv
         CROSS JOIN query_params AS qp
         JOIN player AS p ON p.player_id = cv.player_id
         JOIN club   AS c ON c.club_id   = cv.club_id
WHERE cv.club_id    = qp.subject_id
  AND cv.valid_from <= qp.valid_at AND qp.valid_at < cv.valid_to
  AND cv.tx_from    <= qp.known_at AND qp.known_at < cv.tx_to;


-- =====================================================================
-- Q7 | Contracts active per club per month, as known today.
-- Valid time. A recursive CTE builds the 12 months of the season;
-- every club gets every month (LEFT JOIN), so empty months show 0.
-- "Active in a month" = the contract overlaps the month.
-- =====================================================================
CREATE OR REPLACE VIEW v_q7_monthly_active AS
WITH RECURSIVE months AS (
    SELECT MIN(start_date) AS month_start,
           MAX(end_date)   AS season_end
    FROM season_period
    WHERE name IN ('2025/26 Autumn', '2025/26 Spring')
    UNION ALL
    SELECT month_start + INTERVAL 1 MONTH, season_end
    FROM months
    WHERE month_start + INTERVAL 1 MONTH < season_end
)
SELECT
    DATE_FORMAT(m.month_start, '%Y-%m')  AS month,
    c.short_code                         AS club,
    COUNT(DISTINCT cv.player_id)         AS active_players,
    COUNT(DISTINCT CASE WHEN cv.contract_type = 'LOAN' THEN cv.player_id END) AS on_loan_in
FROM months AS m
         CROSS JOIN club AS c
         LEFT JOIN contract_version AS cv
                   ON  cv.club_id = c.club_id
                       AND cv.tx_to   = '9999-12-31 23:59:59.999999'
                       AND cv.valid_from < m.month_start + INTERVAL 1 MONTH          -- overlaps the month
                       AND m.month_start < cv.valid_to
GROUP BY m.month_start, c.club_id, c.short_code;


-- =====================================================================
-- Q8 | Gaps between two periods of the same player at the same club
-- (left, then came back), as known today.
-- Valid time. LAG gives the end of the previous period;
-- gap = this start - previous end. Only real gaps (> 0 days) are shown.
-- =====================================================================
CREATE OR REPLACE VIEW v_q8_rejoin_gaps AS
WITH ordered AS (
    SELECT
        cv.player_id, cv.club_id, cv.contract_type, cv.valid_from, cv.valid_to,
        LAG(cv.valid_to) OVER (PARTITION BY cv.player_id, cv.club_id
            ORDER BY cv.valid_from) AS prev_valid_to
    FROM contract_version AS cv
    WHERE cv.tx_to = '9999-12-31 23:59:59.999999'
)
SELECT
    p.first_name,
    p.last_name,
    c.short_code                               AS club,
    o.prev_valid_to                            AS left_club_on,
    o.valid_from                               AS came_back_on,
    DATEDIFF(o.valid_from, o.prev_valid_to)    AS days_away,
    o.contract_type                            AS came_back_as
FROM ordered AS o
         JOIN player  AS p ON p.player_id = o.player_id
         JOIN club    AS c ON c.club_id   = o.club_id
WHERE o.prev_valid_to IS NOT NULL
  AND o.valid_from > o.prev_valid_to;