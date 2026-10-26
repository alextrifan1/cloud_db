# Assignment 1 — Two Clocks: Bitemporal Football League

**Engine:** MariaDB 11.8.9 (`SELECT VERSION();` → `11.8.9-MariaDB`)
**GUI used:** DataGrip

## Labels used in this project

- **S1–S23: story events.** Each one is a single change in the league's life
  (a signing, a transfer, a sacking, a typo fixed), numbered in the order the
  database recorded it. S1 is the go-live load in `02_data.sql`; S2–S23 are the
  blocks of `03_timeline.sql`. The same label appears in the story log below,
  in the comment above each block, and at the start of `tx_registry.reason`
  (for example `'S5 | E3+E5: ...'`), so one event can be followed everywhere.
- **E1–E9: event types** defined by the assignment (E2 proactive, E3 late,
  E4 correction, E8 retraction, ...). One story event can have several types:
  S5 is both E3 (recorded late) and E5 (a contract ended).
- **A1-1 – A1-7: extra changes** made only through the stored procedures in
  `06_advanced_a1.sql`, to demonstrate the write API. They are not part of the
  S1–S23 story.

## How to run

Run the scripts in order. `01_schema.sql` drops and recreates the
`football_bt` database, so every run starts from empty.

1. `01_schema.sql` — creates the `football_bt` database and all tables
2. `02_data.sql` — initial load (S1 / E1)
3. `03_timeline.sql` — every later change (S2–S23), in transaction-time order
4. `04_views.sql` — the `query_params` table and one view per question (Q0–Q8)
5. `05_tests.sql` — runs every view with concrete inputs; the expected result is written above each query
6. `06_advanced_a1.sql` (optional) — write API, guard triggers, demo (A1-1 – A1-7) and negative tests.
   Run it once, after 01–05: afterwards direct writes are blocked, so to rerun 05 start again from 01.
7. `06_advanced_a2.sql` (optional) — native temporal tables; Q1, Q5 and Q6 rewritten and compared with the core views.
   Runs after 01–05, with or without A1.

Tip for DataGrip: disconnect before rerunning `01_schema.sql`, so no open tab holds a lock on `football_bt`.

## Views

| Q | View | Question |
|---|---|---|
| Q0 | `v_integrity_violations` | Rows that break I1, I2 or I3 (empty on the final data) |
| Q1 | `v_q1_player_contracts_now` | Current contracts of one player |
| Q2 | `v_q2_head_coach_history` | Head coach tenures of one club, merged, with length |
| Q3 | `v_q3_late_proactive_corrections` | Late (E3), proactive (E2) and corrected (E4) changes, old vs new |
| Q4 | `v_q4_contracts_in_period` | Contracts in a named period: at some point vs throughout |
| Q5 | `v_q5_contracts_believed_at` | All contracts as the database believed them at a moment |
| Q6 | `v_q6_club_as_of` | One club's coach and squad on a date, as known at a moment |
| Q7 | `v_q7_monthly_active` | Active players per club per month |
| Q8 | `v_q8_rejoin_gaps` | Time between leaving a club and rejoining it |

## Time frame

| What | Dates, half-open `[from, to)` |
|---|---|
| Season 2025/26 (valid time) | `[2025-07-01, 2026-07-01)` |
| Named period: 2025/26 Autumn | `[2025-07-01, 2026-01-01)` |
| Named period: 2025/26 Spring | `[2026-01-01, 2026-07-01)` |
| Summer transfer window | `[2025-07-01, 2025-09-02)` — last day 1 Sep |
| Winter transfer window | `[2026-01-05, 2026-02-02)` — last day 1 Feb |
| Go-live (S1) | recorded `2025-07-01 09:00`, valid from `2025-07-01` |

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

| id | Coach | Starts as head coach of |
|---|---|---|
| 1 | Mark Turner | NOR |
| 2 | Paul Weber | RIV |
| 3 | Luca Romano | HAR |
| 4 | Jan Novak | EAS |
| 5 | Daniel Ortiz | WES |
| 6 | Thomas Berg | SOU |
| 7 | Erik Larsen | — (newcomer) |
| 8 | Sam Kelly | — (newcomer) |

**Players:** 70 in total. Ids 1–66 start with permanent contracts, 11 per club in club order
(1–11 NOR, 12–22 RIV, 23–33 HAR, 34–44 EAS, 45–55 WES, 56–66 SOU); ids 67–70 are free agents.
Main characters:

| id | Player | Starts at |
|---|---|---|
| 12 | Sean Hughes | RIV |
| 13 | Lucas Moreau | RIV |
| 23 | Ryan Cole | HAR |
| 34 | Max Fischer | EAS |
| 35 | Tom Baker | EAS |
| 45 | Adam Kowalski | WES |
| 56 | Nico Rossi | SOU |
| 57 | Jonas Meyer | SOU |
| 67 | Leo Martin | free agent |

## Simulated clock

The history is loaded today but must look as if it was written at the time.
Every change in `02_data.sql` and `03_timeline.sql` first sets
`SET @sim_now = '...';`, logs itself in `tx_registry` with that time, and
writes it as `tx_from` on every row it touches. All rows of one change share
one `tx_id` and one `tx_from`.

## Minimum volumes

Measured after 01–03 (current = `tx_to` open; "today" = the date the check was run).

| What | Required | This database |
|---|---|---|
| Main population: players (anchors) | 50 | 70 |
| Role holders: coaches | 5 | 8, all head coach at some point |
| Central objects: clubs | 6 | 6 |
| Relationship facts, current and valid today | 60 | 67 contracts |
| Version rows across all bitemporal tables | 120 | 137 (club 22, contract 101, head coach 14) |
| Valid time covered | 12 months, 2 named periods | 2025-07-01 to 2026-07-01; Autumn and Spring halves |
| Transactions (changes) | — | 23 (S1–S23) |

## Story log

Listed in transaction-time order (the order of `03_timeline.sql`).

| Id | Recorded (tx) | Valid date | What happens | Types |
|---|---|---|---|---|
| S1 | 2025-07-01 09:00 | 2025-07-01 | Go-live: 6 clubs with budgets, 66 contracts, 6 head coaches | E1 |
| S2 | 2025-07-10 10:00 | 2025-07-15 | Free agent Martin signs for HAR, starting in 5 days | E2 |
| S3 | 2025-08-05 11:00 | ends 2025-08-04 | Cole leaves HAR (mutual termination) | E5 |
| S4 | 2025-08-20 12:00 | 2025-08-25 → 2026-07-01 | Fischer loaned EAS → SOU; same tx: SOU budget drops by the loan fee from 25 Aug | E2, E9 |
| S5 | 2025-09-12 09:30 | 2025-09-01 | Hughes transfers RIV → WES on deadline day, registered 11 days late, after the window closed | E3, E5 |
| S6 | 2025-09-15 08:00 | 2025-09-15 | Clerk wrongly enters a loan of Rossi to NOR (never agreed) | E8 setup, retracted in S7 |
| S7 | 2025-09-15 16:30 | — | That loan is retracted: it never happened | E8 |
| S8 | 2025-10-06 18:00 | 2025-10-06 | RIV sacks Weber mid-season; Larsen takes over the same day | E7 |
| S9 | 2025-10-20 10:00 | from 2025-07-01 | Kowalski's salary was typed 450,000 at go-live; it is really 540,000 | E4 |
| S10 | 2025-11-30 17:00 | ends 2025-11-30 | SOU releases Meyer | E5 |
| S11 | 2025-12-15 10:00 | 2026-01-01 | 8 NOR players get salary raises from New Year | E2 |
| S12 | 2025-12-20 10:00 | 2026-01-01 | All 6 clubs' spring budgets set | E2 |
| S13 | 2026-01-16 09:00 | ends 2026-01-15 | Fischer's loan at SOU cut short; he is back at EAS full-time | E5 |
| S14 | 2026-01-19 14:00 | 2026-01-20 → 2026-07-01 | Hughes returns to RIV on loan from WES (gap since Sept) | E2, E6 |
| S15 | 2026-01-20 11:00 | 2026-01-10 | Cole rejoins HAR, recorded 10 days late (gap since Aug) | E3, E6 |
| S16 | 2026-01-28 15:00 | 2026-02-01 | Meyer rejoins SOU (gap since Nov) | E2, E6 |
| S17 | 2026-02-11 10:00 | 2026-02-01 | Baker transfers EAS → NOR, registered 10 days late, after the winter window | E3, E5 |
| S18 | 2026-02-20 12:00 | 2026-02-10 | Meyer's return date was wrong: actually 10 Feb, not 1 Feb | E4 |
| S19 | 2026-03-16 10:00 | 2026-03-02 | HAR: clerk records Romano sacked, Kelly in charge from 2 Mar (14 days late) | E3, E7 |
| S20 | 2026-03-23 15:00 | 2026-03-06 | Sacking date disputed: the real handover was 6 Mar; corrected | E4, E7 |
| S21 | 2026-04-02 09:00 | 2026-04-01 | WES takeover: same tx: budget raised and Ortiz replaced by Weber | E7, E9 |
| S22 | 2026-04-10 10:00 | 2026-03-01 | Moreau's raise at RIV, recorded 40 days late | E3 |
| S23 | 2026-05-20 12:00 | 2026-07-01 | Moreau pre-signs with NOR from 1 July; his RIV contract ends 30 June | E2, E5 |

## The three-answers case (S19 and S20)

**Who was head coach of HAR on 4 March 2026?**

| Known at | Answer | Why |
|---|---|---|
| 2026-03-10 | Romano | nothing recorded yet |
| 2026-03-20 | Kelly | S19 says Kelly from 2 Mar |
| today | Romano | S20 moved the handover to 6 Mar |

## Event coverage

| Type | Required | Story events |
|---|---|---|
| E1 Initial load | 1 | S1 |
| E2 Proactive | 3 | S2, S4, S11, S12, S14, S16, S23 |
| E3 Late entry (≥ 7 days) | 5 | S5, S15, S17, S19, S22 |
| E4 Correction | 3 | S9, S18, S20 |
| E5 Real-world end | 5 | S3, S5, S10, S13, S17, S23 |
| E6 Restart after gap | 3 | S14 (Hughes/RIV), S15 (Cole/HAR), S16 (Meyer/SOU) |
| E7 Role holder change (2+ clubs, one mid-period, one later corrected) | 3 | S8 (RIV, mid-season), S19 + S20 (HAR, later corrected), S21 (WES) |
| E8 Retraction | 1 | S7 |
| E9 Multi-table change | 2 | S4, S21 |

## A1 demo changes (`06_advanced_a1.sql`)

Made only through the write API, after the S1–S23 story. All valid dates are from 1 July 2026 on,
so the Part C results do not change.

| Id | Recorded (tx) | Valid date | What happens | Procedure |
|---|---|---|---|---|
| A1-1 | 2026-06-05 10:00 | 2026-07-01 | Free agent Hansen signs for EAS | `sp_assert_fact` |
| A1-2 | 2026-06-10 10:00 | 2026-07-01 | Walsh gets a raise at NOR | `sp_assert_fact` |
| A1-3 | 2026-06-12 09:00 | from 2026-07-01 | Hansen's salary was typed wrong: 260,000 → 290,000 | `sp_correct_fact` |
| A1-4 | 2026-06-15 11:00 | ends 2026-09-01 | Lopes leaves SOU after 31 Aug | `sp_end_fact` |
| A1-5 | 2026-06-20 08:00 | 2026-07-01 | Lindqvist signed for WES by mistake | `sp_assert_fact` |
| A1-6 | 2026-06-20 15:00 | — | That contract is retracted: it never existed | `sp_retract_fact` |
| A1-7 | real clock | ends 2027-01-01 | Hansen's contract will end on 31 Dec 2026 (`@sim_now` cleared) | `sp_end_fact` |