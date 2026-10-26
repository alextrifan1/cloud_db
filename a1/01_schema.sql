-- 01_schema.sql: football league with two clocks (MariaDB 11.8)
-- drops and recreates the db, safe to rerun

DROP DATABASE IF EXISTS football_bt;

CREATE DATABASE football_bt
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

USE football_bt;

SET time_zone = '+00:00';
-- all times in UTC


-- ---------- helper tables (no history) ----------

-- one row per change, all rows of a change share tx_id and tx_time
-- only ever inserted into, so it's already a history
CREATE TABLE tx_registry
(
    tx_id   BIGINT       NOT NULL AUTO_INCREMENT,
    tx_time DATETIME(6)  NOT NULL, -- from @sim_now
    author  VARCHAR(100) NOT NULL,
    reason  VARCHAR(500) NOT NULL, -- starts with the label, e.g. 'S5 | E3 ...'
    PRIMARY KEY (tx_id)
);

-- named periods for Q4 (season halves, transfer windows)
-- the calendar never changes, so no history
CREATE TABLE season_period
(
    period_id  INT         NOT NULL AUTO_INCREMENT,
    name       VARCHAR(50) NOT NULL,
    start_date DATE        NOT NULL, -- included
    end_date   DATE        NOT NULL, -- excluded
    PRIMARY KEY (period_id),
    UNIQUE (name),
    CHECK (start_date < end_date)
);


-- ---------- anchors (no history) ----------
-- ids + facts that never change. FKs point here, since a version
-- table has many rows per entity and can't be an FK target.

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


-- ---------- version tables (bitemporal) ----------
-- one row = a fact + when it was true + when the db believed it

-- club name and budget. its valid periods also bound
-- the club's contracts and coaches (I2)
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

-- player at a club (relationship), the biggest table
-- key (player_id, club_id), so a player can leave and come back.
-- a loan is a LOAN row at the new club, the PERMANENT one keeps running
CREATE TABLE contract_version
(
    version_id    BIGINT                     NOT NULL AUTO_INCREMENT,
    player_id     INT                        NOT NULL,
    club_id       INT                        NOT NULL,
    contract_type ENUM ('PERMANENT', 'LOAN') NOT NULL,
    salary_eur    DECIMAL(12, 2)             NOT NULL, -- yearly
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
    -- as-of indexes: by player (Q1) and by club (Q6)
    INDEX ix_contract_asof (player_id, tx_to, valid_from),
    INDEX ix_contract_club_asof (club_id, tx_to, valid_from)
);

-- head coach of a club (role), key club_id
-- at most one coach per club at a time (I3)
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
    -- as-of index: club, then tx_to, then valid_from
    INDEX ix_coach_asof (club_id, tx_to, valid_from)
);