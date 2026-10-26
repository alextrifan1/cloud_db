-- 02_data.sql: S1 | E1, initial load on go-live day
-- every version row is valid from 2025-07-01

USE football_bt;
SET time_zone = '+00:00';

START TRANSACTION;


-- simulated clock, go-live morning (used as tx_from below)
SET @sim_now = '2025-07-01 09:00:00';


-- log the change, keep its id (1) for every row below
INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'system', 'S1 | E1 initial load: go-live of the league database');

SET @tx_id = LAST_INSERT_ID();


-- named periods, end_date = first day after
INSERT INTO season_period (period_id, name, start_date, end_date)
VALUES (1, '2025/26 Autumn', '2025-07-01', '2026-01-01'),
       (2, '2025/26 Spring', '2026-01-01', '2026-07-01'),
       (3, 'Summer window 2025', '2025-07-01', '2025-09-02'),
       (4, 'Winter window 2026', '2026-01-05', '2026-02-02');


-- ---------- anchors ----------
-- ids set by hand so 03 can use them

INSERT INTO club (club_id, short_code)
VALUES (1, 'NOR'),
       (2, 'RIV'),
       (3, 'HAR'),
       (4, 'EAS'),
       (5, 'WES'),
       (6, 'SOU');

-- 1-6 start as head coaches, 7 and 8 come later
INSERT INTO coach (coach_id, first_name, last_name)
VALUES (1, 'Mark', 'Turner'),
       (2, 'Paul', 'Weber'),
       (3, 'Luca', 'Romano'),
       (4, 'Jan', 'Novak'),
       (5, 'Daniel', 'Ortiz'),
       (6, 'Thomas', 'Berg'),
       (7, 'Erik', 'Larsen'),
       (8, 'Sam', 'Kelly');

-- 11 per club in order (1-11 NOR, 12-22 RIV, ...), 67-70 free agents
INSERT INTO player (player_id, first_name, last_name, birth_date)
VALUES
    -- NOR
    (1, 'Ethan', 'Walsh', '1998-03-14'),
    (2, 'Oliver', 'Grant', '1996-11-02'),
    (3, 'Noah', 'Fletcher', '2000-05-21'),
    (4, 'Liam', 'Porter', '1997-08-09'),
    (5, 'Mason', 'Reid', '1999-01-30'),
    (6, 'Jack', 'Dawson', '1995-06-17'),
    (7, 'Henry', 'Clarke', '2001-09-05'),
    (8, 'Owen', 'Barnes', '1994-12-12'),
    (9, 'Caleb', 'Shaw', '2002-04-25'),
    (10, 'Isaac', 'Lowe', '1998-10-08'),
    (11, 'Dylan', 'Burke', '2003-02-19'),
    -- RIV
    (12, 'Sean', 'Hughes', '1999-07-11'),
    (13, 'Lucas', 'Moreau', '1997-04-03'),
    (14, 'Hugo', 'Lambert', '2000-12-01'),
    (15, 'Felix', 'Dubois', '1996-02-27'),
    (16, 'Theo', 'Girard', '2001-06-15'),
    (17, 'Arthur', 'Blanc', '1995-09-23'),
    (18, 'Louis', 'Fontaine', '1998-05-06'),
    (19, 'Jules', 'Mercier', '2002-08-30'),
    (20, 'Adrian', 'Vidal', '1997-11-18'),
    (21, 'Mateo', 'Ruiz', '1999-03-09'),
    (22, 'Diego', 'Navarro', '2000-10-26'),
    -- HAR
    (23, 'Ryan', 'Cole', '1996-01-13'),
    (24, 'Marco', 'Bianchi', '1998-07-29'),
    (25, 'Matteo', 'Ferri', '2000-02-04'),
    (26, 'Luca', 'Conti', '1997-10-16'),
    (27, 'Paolo', 'Greco', '1995-04-22'),
    (28, 'Davide', 'Marino', '2001-11-07'),
    (29, 'Simone', 'Gallo', '1999-06-01'),
    (30, 'Andrea', 'Costa', '2002-01-24'),
    (31, 'Fabio', 'Rizzi', '1996-08-19'),
    (32, 'Enzo', 'Moretti', '1998-12-28'),
    (33, 'Gianni', 'Testa', '2003-05-10'),
    -- EAS
    (34, 'Max', 'Fischer', '1999-02-08'),
    (35, 'Tom', 'Baker', '1997-09-14'),
    (36, 'Jan', 'Schulz', '2000-03-03'),
    (37, 'Felix', 'Wagner', '1996-07-20'),
    (38, 'Paul', 'Becker', '1998-11-11'),
    (39, 'Lukas', 'Hoffmann', '2001-04-17'),
    (40, 'Tim', 'Koch', '1995-10-02'),
    (41, 'Nils', 'Richter', '2002-06-26'),
    (42, 'Erik', 'Wolf', '1997-01-05'),
    (43, 'Moritz', 'Klein', '1999-08-31'),
    (44, 'Finn', 'Braun', '2003-12-14'),
    -- WES
    (45, 'Adam', 'Kowalski', '1997-05-28'),
    (46, 'Piotr', 'Wozniak', '1999-10-12'),
    (47, 'Kamil', 'Mazur', '2000-01-18'),
    (48, 'Tomasz', 'Krol', '1996-04-09'),
    (49, 'Jakub', 'Wojcik', '2001-07-23'),
    (50, 'Marek', 'Dudek', '1995-12-04'),
    (51, 'Pavel', 'Horak', '1998-02-15'),
    (52, 'Ondrej', 'Svoboda', '2002-09-27'),
    (53, 'Martin', 'Dvorak', '1997-06-08'),
    (54, 'Lukas', 'Cerny', '1999-11-29'),
    (55, 'Filip', 'Benes', '2003-03-16'),
    -- SOU
    (56, 'Nico', 'Rossi', '1998-04-12'),
    (57, 'Jonas', 'Meyer', '1996-10-30'),
    (58, 'Carlos', 'Mendes', '2000-07-07'),
    (59, 'Rafael', 'Silva', '1997-02-21'),
    (60, 'Bruno', 'Teixeira', '1999-05-13'),
    (61, 'Tiago', 'Ferreira', '2001-01-09'),
    (62, 'Joao', 'Pereira', '1995-08-25'),
    (63, 'Miguel', 'Santos', '1998-03-28'),
    (64, 'Pedro', 'Almeida', '2002-11-03'),
    (65, 'Rui', 'Carvalho', '1996-06-19'),
    (66, 'Andre', 'Lopes', '2003-09-01'),
    -- no club yet
    (67, 'Leo', 'Martin', '1998-08-16'),
    (68, 'Samuel', 'Ward', '1994-05-02'),
    (69, 'Victor', 'Hansen', '1996-12-20'),
    (70, 'Oscar', 'Lindqvist', '1999-04-07');


-- ---------- version rows ----------
-- valid_to and tx_to left out, defaults make them open-ended

-- names and autumn budgets
INSERT INTO club_version (club_id, name, budget_eur, valid_from, tx_from, tx_id)
VALUES (1, 'Northside FC', 12000000.00, '2025-07-01', @sim_now, @tx_id),
       (2, 'Riverside United', 9500000.00, '2025-07-01', @sim_now, @tx_id),
       (3, 'Harbor City', 8000000.00, '2025-07-01', @sim_now, @tx_id),
       (4, 'Eastfield Rovers', 7200000.00, '2025-07-01', @sim_now, @tx_id),
       (5, 'Westbrook Athletic', 6500000.00, '2025-07-01', @sim_now, @tx_id),
       (6, 'Southport Town', 5800000.00, '2025-07-01', @sim_now, @tx_id);

-- coach N heads club N
INSERT INTO head_coach_version (club_id, coach_id, valid_from, tx_from, tx_id)
VALUES (1, 1, '2025-07-01', @sim_now, @tx_id),
       (2, 2, '2025-07-01', @sim_now, @tx_id),
       (3, 3, '2025-07-01', @sim_now, @tx_id),
       (4, 4, '2025-07-01', @sim_now, @tx_id),
       (5, 5, '2025-07-01', @sim_now, @tx_id),
       (6, 6, '2025-07-01', @sim_now, @tx_id);

-- one permanent contract each for 1-66, yearly salary
INSERT INTO contract_version
(player_id, club_id, contract_type, salary_eur, valid_from, tx_from, tx_id)
VALUES
    -- NOR
    (1, 1, 'PERMANENT', 850000.00, '2025-07-01', @sim_now, @tx_id),
    (2, 1, 'PERMANENT', 620000.00, '2025-07-01', @sim_now, @tx_id),
    (3, 1, 'PERMANENT', 410000.00, '2025-07-01', @sim_now, @tx_id),
    (4, 1, 'PERMANENT', 530000.00, '2025-07-01', @sim_now, @tx_id),
    (5, 1, 'PERMANENT', 380000.00, '2025-07-01', @sim_now, @tx_id),
    (6, 1, 'PERMANENT', 720000.00, '2025-07-01', @sim_now, @tx_id),
    (7, 1, 'PERMANENT', 300000.00, '2025-07-01', @sim_now, @tx_id),
    (8, 1, 'PERMANENT', 480000.00, '2025-07-01', @sim_now, @tx_id),
    (9, 1, 'PERMANENT', 250000.00, '2025-07-01', @sim_now, @tx_id),
    (10, 1, 'PERMANENT', 350000.00, '2025-07-01', @sim_now, @tx_id),
    (11, 1, 'PERMANENT', 220000.00, '2025-07-01', @sim_now, @tx_id),
    -- RIV
    (12, 2, 'PERMANENT', 560000.00, '2025-07-01', @sim_now, @tx_id),
    (13, 2, 'PERMANENT', 640000.00, '2025-07-01', @sim_now, @tx_id),
    (14, 2, 'PERMANENT', 330000.00, '2025-07-01', @sim_now, @tx_id),
    (15, 2, 'PERMANENT', 470000.00, '2025-07-01', @sim_now, @tx_id),
    (16, 2, 'PERMANENT', 290000.00, '2025-07-01', @sim_now, @tx_id),
    (17, 2, 'PERMANENT', 510000.00, '2025-07-01', @sim_now, @tx_id),
    (18, 2, 'PERMANENT', 400000.00, '2025-07-01', @sim_now, @tx_id),
    (19, 2, 'PERMANENT', 240000.00, '2025-07-01', @sim_now, @tx_id),
    (20, 2, 'PERMANENT', 360000.00, '2025-07-01', @sim_now, @tx_id),
    (21, 2, 'PERMANENT', 430000.00, '2025-07-01', @sim_now, @tx_id),
    (22, 2, 'PERMANENT', 270000.00, '2025-07-01', @sim_now, @tx_id),
    -- HAR
    (23, 3, 'PERMANENT', 490000.00, '2025-07-01', @sim_now, @tx_id),
    (24, 3, 'PERMANENT', 380000.00, '2025-07-01', @sim_now, @tx_id),
    (25, 3, 'PERMANENT', 310000.00, '2025-07-01', @sim_now, @tx_id),
    (26, 3, 'PERMANENT', 450000.00, '2025-07-01', @sim_now, @tx_id),
    (27, 3, 'PERMANENT', 520000.00, '2025-07-01', @sim_now, @tx_id),
    (28, 3, 'PERMANENT', 260000.00, '2025-07-01', @sim_now, @tx_id),
    (29, 3, 'PERMANENT', 340000.00, '2025-07-01', @sim_now, @tx_id),
    (30, 3, 'PERMANENT', 230000.00, '2025-07-01', @sim_now, @tx_id),
    (31, 3, 'PERMANENT', 410000.00, '2025-07-01', @sim_now, @tx_id),
    (32, 3, 'PERMANENT', 370000.00, '2025-07-01', @sim_now, @tx_id),
    (33, 3, 'PERMANENT', 200000.00, '2025-07-01', @sim_now, @tx_id),
    -- EAS
    (34, 4, 'PERMANENT', 470000.00, '2025-07-01', @sim_now, @tx_id),
    (35, 4, 'PERMANENT', 420000.00, '2025-07-01', @sim_now, @tx_id),
    (36, 4, 'PERMANENT', 300000.00, '2025-07-01', @sim_now, @tx_id),
    (37, 4, 'PERMANENT', 390000.00, '2025-07-01', @sim_now, @tx_id),
    (38, 4, 'PERMANENT', 350000.00, '2025-07-01', @sim_now, @tx_id),
    (39, 4, 'PERMANENT', 280000.00, '2025-07-01', @sim_now, @tx_id),
    (40, 4, 'PERMANENT', 440000.00, '2025-07-01', @sim_now, @tx_id),
    (41, 4, 'PERMANENT', 220000.00, '2025-07-01', @sim_now, @tx_id),
    (42, 4, 'PERMANENT', 330000.00, '2025-07-01', @sim_now, @tx_id),
    (43, 4, 'PERMANENT', 360000.00, '2025-07-01', @sim_now, @tx_id),
    (44, 4, 'PERMANENT', 190000.00, '2025-07-01', @sim_now, @tx_id),
    -- WES
    -- 45 Kowalski: 450k is a planted typo, S9 fixes it to 540k
    (45, 5, 'PERMANENT', 450000.00, '2025-07-01', @sim_now, @tx_id),
    (46, 5, 'PERMANENT', 340000.00, '2025-07-01', @sim_now, @tx_id),
    (47, 5, 'PERMANENT', 290000.00, '2025-07-01', @sim_now, @tx_id),
    (48, 5, 'PERMANENT', 380000.00, '2025-07-01', @sim_now, @tx_id),
    (49, 5, 'PERMANENT', 250000.00, '2025-07-01', @sim_now, @tx_id),
    (50, 5, 'PERMANENT', 410000.00, '2025-07-01', @sim_now, @tx_id),
    (51, 5, 'PERMANENT', 320000.00, '2025-07-01', @sim_now, @tx_id),
    (52, 5, 'PERMANENT', 210000.00, '2025-07-01', @sim_now, @tx_id),
    (53, 5, 'PERMANENT', 360000.00, '2025-07-01', @sim_now, @tx_id),
    (54, 5, 'PERMANENT', 300000.00, '2025-07-01', @sim_now, @tx_id),
    (55, 5, 'PERMANENT', 180000.00, '2025-07-01', @sim_now, @tx_id),
    -- SOU
    (56, 6, 'PERMANENT', 400000.00, '2025-07-01', @sim_now, @tx_id),
    (57, 6, 'PERMANENT', 350000.00, '2025-07-01', @sim_now, @tx_id),
    (58, 6, 'PERMANENT', 280000.00, '2025-07-01', @sim_now, @tx_id),
    (59, 6, 'PERMANENT', 330000.00, '2025-07-01', @sim_now, @tx_id),
    (60, 6, 'PERMANENT', 260000.00, '2025-07-01', @sim_now, @tx_id),
    (61, 6, 'PERMANENT', 240000.00, '2025-07-01', @sim_now, @tx_id),
    (62, 6, 'PERMANENT', 370000.00, '2025-07-01', @sim_now, @tx_id),
    (63, 6, 'PERMANENT', 300000.00, '2025-07-01', @sim_now, @tx_id),
    (64, 6, 'PERMANENT', 200000.00, '2025-07-01', @sim_now, @tx_id),
    (65, 6, 'PERMANENT', 310000.00, '2025-07-01', @sim_now, @tx_id),
    (66, 6, 'PERMANENT', 190000.00, '2025-07-01', @sim_now, @tx_id);


COMMIT;