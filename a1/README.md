# Assignment 1 — Two Clocks: Bitemporal Football League

**Engine:** MariaDB 11.x  <!-- replace with the exact output of: SELECT VERSION(); -->
**GUI used:** HeidiSQL

## How to run

Run the scripts in order on an empty server (each one is re-runnable):

1. `01_schema.sql` — creates the `football_bt` database and all tables
2. `02_data.sql` — initial load (event 1 / E1)
3. `03_timeline.sql` — every later change, in transaction-time order
4. `04_views.sql` — one view per question (Q0–Q8)
5. `05_tests.sql` — runs every view with concrete parameters

## Time frame

| What | Dates, half-open `[from, to)` |
|---|---|
| Season 2025/26 (valid time) | `[2025-07-01, 2026-07-01)` |
| Named period: 2025/26 Autumn | `[2025-07-01, 2026-01-01)` |
| Named period: 2025/26 Spring | `[2026-01-01, 2026-07-01)` |
| Summer transfer window | `[2025-07-01, 2025-09-02)` — last day 1 Sep |
| Winter transfer window | `[2026-01-05, 2026-02-02)` — last day 1 Feb |
| Go-live (E1) | recorded `2025-07-01 09:00`, valid from `2025-07-01` |

## Cast

**Clubs**

| id | Code | Name |
|---|---|---|
| 1 | NOR | Northside FC |
| 2 | RIV | Riverside United |
| 3 | HAR | Harbor City |
| 4 | EAS | Eastfield Rovers |
| 5 | WES | Westbrook Athletic |
| 6 | SOU | Southport Town |

**Coaches**

| Coach | Starts as head coach of |
|---|---|
| Mark Turner | NOR |
| Paul Weber | RIV |
| Luca Romano | HAR |
| Jan Novak | EAS |
| Daniel Ortiz | WES |
| Thomas Berg | SOU |
| Erik Larsen | — (newcomer) |
| Sam Kelly | — (newcomer) |

**Players:** 70 in total: 66 start with permanent contracts (11 per club), 4 are free agents.
Main characters of the story:

| Player | Starts at |
|---|---|
| Leo Martin | free agent |
| Ryan Cole | HAR |
| Max Fischer | EAS |
| Sean Hughes | RIV |
| Nico Rossi | SOU |
| Adam Kowalski | WES |
| Jonas Meyer | SOU |
| Tom Baker | EAS |
| Lucas Moreau | RIV |

## Story log

Listed in transaction-time order (the order of `03_timeline.sql`).

| # | Recorded (tx) | Valid date | What happens | Types |
|---|---|---|---|---|
| 1 | 2025-07-01 09:00 | 2025-07-01 | Go-live: 6 clubs with budgets, 66 contracts, 6 head coaches | E1 |
| 2 | 2025-07-10 10:00 | 2025-07-15 | Free agent Martin signs for HAR, starting in 5 days | E2 |
| 3 | 2025-08-05 11:00 | ends 2025-08-04 | Cole leaves HAR (mutual termination) | E5 |
| 4 | 2025-08-20 12:00 | 2025-08-25 → 2026-07-01 | Fischer loaned EAS → SOU; same tx: SOU budget drops by the loan fee from 25 Aug | E2, E9 |
| 5 | 2025-09-12 09:30 | 2025-09-01 | Hughes transfers RIV → WES on deadline day, registered 11 days late, after the window closed | E3, E5 |
| 6 | 2025-09-15 08:00 | 2025-09-15 | Clerk wrongly enters a loan of Rossi to NOR | (the mistake) |
| 7 | 2025-09-15 16:30 | — | That loan is retracted: it never happened | E8 |
| 8 | 2025-10-06 18:00 | 2025-10-06 | RIV sacks Weber mid-season; Larsen takes over the same day | E7 |
| 9 | 2025-10-20 10:00 | from 2025-07-01 | Kowalski's salary was typed 450,000 at go-live; it is really 540,000 | E4 |
| 10 | 2025-11-30 17:00 | ends 2025-11-30 | SOU releases Meyer | E5 |
| 11 | 2025-12-15 10:00 | 2026-01-01 | 8 NOR players get salary raises from New Year | E2 |
| 12 | 2025-12-20 10:00 | 2026-01-01 | All 6 clubs' spring budgets set | E2 |
| 13 | 2026-01-16 09:00 | ends 2026-01-15 | Fischer's loan at SOU cut short; he is back at EAS full-time | E5 |
| 14 | 2026-01-19 14:00 | 2026-01-20 → 2026-07-01 | Hughes returns to RIV on loan from WES (gap since Sept) | E2, E6 |
| 15 | 2026-01-20 11:00 | 2026-01-10 | Cole rejoins HAR, recorded 10 days late (gap since Aug) | E3, E6 |
| 16 | 2026-01-28 15:00 | 2026-02-01 | Meyer rejoins SOU (gap since Nov) | E2, E6 |
| 17 | 2026-02-11 10:00 | 2026-02-01 | Baker transfers EAS → NOR, registered 10 days late, after the winter window | E3, E5 |
| 18 | 2026-02-20 12:00 | 2026-02-10 | Meyer's return date was wrong: actually 10 Feb, not 1 Feb | E4 |
| 19 | 2026-03-16 10:00 | 2026-03-02 | HAR: clerk records Romano sacked, Kelly in charge from 2 Mar (14 days late) | E3, E7 |
| 20 | 2026-03-23 15:00 | 2026-03-06 | Sacking date disputed: the real handover was 6 Mar; corrected | E4, E7 |
| 21 | 2026-04-02 09:00 | 2026-04-01 | WES takeover: same tx: budget raised and Ortiz replaced by Weber | E7, E9 |
| 22 | 2026-04-10 10:00 | 2026-03-01 | Moreau's raise at RIV, recorded 40 days late | E3 |
| 23 | 2026-05-20 12:00 | 2026-07-01 | Moreau pre-signs with NOR from 1 July; his RIV contract ends 30 June | E2, E5 |

## The three-answers case (events 19 and 20)

**Who was head coach of HAR on 4 March 2026?**

| Known at | Answer | Why |
|---|---|---|
| 2026-03-10 | Romano | nothing recorded yet |
| 2026-03-20 | Kelly | event 19 says Kelly from 2 Mar |
| today | Romano | event 20 moved the handover to 6 Mar |

## Event coverage

| Type | Required | Events |
|---|---|---|
| E1 Initial load | 1 | 1 |
| E2 Proactive | 3 | 2, 4, 11, 12, 14, 16, 23 |
| E3 Late entry (≥ 7 days) | 5 | 5, 15, 17, 19, 22 |
| E4 Correction | 3 | 9, 18, 20 |
| E5 Real-world end | 5 | 3, 5, 10, 13, 17, 23 |
| E6 Restart after gap | 3 | 14 (Hughes/RIV), 15 (Cole/HAR), 16 (Meyer/SOU) |
| E7 Role holder change | 3 | 8 (RIV), 19 + 20 (HAR), 21 (WES) |
| E8 Retraction | 1 | 7 |
| E9 Multi-table change | 2 | 4, 21 |