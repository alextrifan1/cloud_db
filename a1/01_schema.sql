-- 01_schema.sql
-- Football league with two clocks. MariaDB 11.x.

DROP DATABASE IF EXISTS football_bt;

CREATE DATABASE football_bt
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

USE football_bt;

SET time_zone = '+00:00';
-- store all times as UTC


-- =====================================================================
-- Non-temporal helper tables
-- =====================================================================

-- Log of changes, one row per change.
-- All rows written by one change share its tx_id and tx_time.
-- No history needed: this table is the history of writes, rows are only added.
CREATE TABLE tx_registry
(
    tx_id   BIGINT       NOT NULL AUTO_INCREMENT,
    tx_time DATETIME(6)  NOT NULL, -- taken from @sim_now
    author  VARCHAR(100) NOT NULL,
    reason  VARCHAR(500) NOT NULL, -- starts with the story label, e.g. 'S5 | E3 ...'
    PRIMARY KEY (tx_id)
);

-- Named date ranges: season halves and transfer windows (used by Q4).
-- No history needed: the league calendar is fixed and never revised.
CREATE TABLE season_period
(
    period_id  INT         NOT NULL AUTO_INCREMENT,
    name       VARCHAR(50) NOT NULL,
    start_date DATE        NOT NULL, -- included
    end_date   DATE        NOT NULL, -- not included
    PRIMARY KEY (period_id),
    UNIQUE (name),
    CHECK (start_date < end_date)
);


-- =====================================================================
-- Anchor tables (non-temporal)
-- Only ids and facts that never change. Every foreign key points here,
-- because a history table has many rows per entity and cannot be a target.
-- =====================================================================

CREATE TABLE club
(
    club_id    INT     NOT NULL AUTO_INCREMENT,
    short_code CHAR(3) NOT NULL, -- e.g. 'NOR'
    PRIMARY KEY (club_id),
    UNIQUE (short_code)
);

CREATE TABLE player
(
    player_id  INT         NOT NULL AUTO_INCREMENT,
    first_name VARCHAR(50) NOT NULL,
    last_name  VARCHAR(50) NOT NULL,
    birth_date DATE        NOT NULL,
    PRIMARY KEY (player_id)
);

CREATE TABLE coach
(
    coach_id   INT         NOT NULL AUTO_INCREMENT,
    first_name VARCHAR(50) NOT NULL,
    last_name  VARCHAR(50) NOT NULL,
    PRIMARY KEY (coach_id)
);


-- =====================================================================
-- History tables (bitemporal)
-- One row = one fact + when it was true + when it was believed.
-- =====================================================================

-- Club name and budget over time.
-- budget_eur is the number that changes. The club's valid periods are
-- also the limit for its contracts and coaches (invariant I2).
CREATE TABLE club_version
(
    version_id BIGINT         NOT NULL AUTO_INCREMENT,
    club_id    INT            NOT NULL,
    name       VARCHAR(100)   NOT NULL,
    budget_eur DECIMAL(14, 2) NOT NULL,
    valid_from DATE           NOT NULL,
    valid_to   DATE           NOT NULL DEFAULT '9999-12-31',
    tx_from    DATETIME(6)    NOT NULL,
    tx_to      DATETIME(6)    NOT NULL DEFAULT '9999-12-31 23:59:59.999999',
    tx_id      BIGINT         NOT NULL,
    PRIMARY KEY (version_id),
    FOREIGN KEY (club_id) REFERENCES club (club_id),
    FOREIGN KEY (tx_id) REFERENCES tx_registry (tx_id),
    CHECK (budget_eur >= 0),
    CHECK (valid_from < valid_to),
    CHECK (tx_from < tx_to)
);

-- A player plays for a club (the relationship). Largest table.
-- Key: (player_id, club_id), so the same pair can stop and start again.
-- A loan is a LOAN row at the borrowing club; the PERMANENT row at the
-- home club keeps running at the same time.
CREATE TABLE contract_version
(
    version_id    BIGINT                     NOT NULL AUTO_INCREMENT,
    player_id     INT                        NOT NULL,
    club_id       INT                        NOT NULL,
    contract_type ENUM ('PERMANENT', 'LOAN') NOT NULL,
    salary_eur    DECIMAL(12, 2)             NOT NULL, -- per year
    valid_from    DATE                       NOT NULL,
    valid_to      DATE                       NOT NULL DEFAULT '9999-12-31',
    tx_from       DATETIME(6)                NOT NULL,
    tx_to         DATETIME(6)                NOT NULL DEFAULT '9999-12-31 23:59:59.999999',
    tx_id         BIGINT                     NOT NULL,
    PRIMARY KEY (version_id),
    FOREIGN KEY (player_id) REFERENCES player (player_id),
    FOREIGN KEY (club_id) REFERENCES club (club_id),
    FOREIGN KEY (tx_id) REFERENCES tx_registry (tx_id),
    CHECK (salary_eur > 0),
    CHECK (valid_from < valid_to),
    CHECK (tx_from < tx_to),
    -- As-of index: jump to one player, then filter by tx_to, then valid_from.
    INDEX ix_contract_asof (player_id, tx_to, valid_from)
);

-- Head coach of a club (the role).
-- Key: club_id. A club has at most one head coach at a time (invariant I3).
CREATE TABLE head_coach_version
(
    version_id BIGINT      NOT NULL AUTO_INCREMENT,
    club_id    INT         NOT NULL,
    coach_id   INT         NOT NULL,
    valid_from DATE        NOT NULL,
    valid_to   DATE        NOT NULL DEFAULT '9999-12-31',
    tx_from    DATETIME(6) NOT NULL,
    tx_to      DATETIME(6) NOT NULL DEFAULT '9999-12-31 23:59:59.999999',
    tx_id      BIGINT      NOT NULL,
    PRIMARY KEY (version_id),
    FOREIGN KEY (club_id) REFERENCES club (club_id),
    FOREIGN KEY (coach_id) REFERENCES coach (coach_id),
    FOREIGN KEY (tx_id) REFERENCES tx_registry (tx_id),
    CHECK (valid_from < valid_to),
    CHECK (tx_from < tx_to),
    -- As-of index: jump to one club, then filter by tx_to, then valid_from.
    INDEX ix_coach_asof (club_id, tx_to, valid_from)
);