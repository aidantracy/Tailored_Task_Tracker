-- db/seed.sql — demo-rich seed (20 tasks total, with notes)
-- Matches your 5 dashboard steps; each task includes a 'notes' value.

SET @OLD_FK = @@FOREIGN_KEY_CHECKS; SET FOREIGN_KEY_CHECKS = 0;
USE `dashboard`;

-- Optional: clean dev data so this seed is deterministic
TRUNCATE TABLE `Comments`;
TRUNCATE TABLE `User_Task_Read_Markers`;
TRUNCATE TABLE `Task`;
TRUNCATE TABLE `Recurring_Task`;
TRUNCATE TABLE `Step`;
TRUNCATE TABLE `Status`;
TRUNCATE TABLE `Users`;
TRUNCATE TABLE `Invitation_Keys`;
TRUNCATE TABLE `Timestamps`;
TRUNCATE TABLE `Audit_Log`;
TRUNCATE TABLE `Business_Day`;
TRUNCATE TABLE `Dashboard`;

SET FOREIGN_KEY_CHECKS = 1;

-- 1) Reference data
INSERT INTO `Status` (`status`, `color_code`) VALUES
  ('Not Started', '#CBD5E1'),
  ('Not Expected', '#E7E5E4'),
  ('In Progress', '#FACC15'),
  ('Stuck',       '#F97316'),
  ('Done',        '#22C55E');

-- Ensure Business_Day has all needed target calendar days
INSERT INTO `Business_Day` (`business_day`) VALUES
  (1),(2),(3),(4),(5),(6),(7),(8),(9),(10),
  (11),(12),(13),(14),(15),(16),(17),(18),(19),(20),
  (21),(22),(23),(24),(25),(26),(27),(28),(29),(30),(31);

-- 2) A dashboard that includes today
INSERT INTO `Dashboard` (`start_date`, `end_date`, `month_key`)
VALUES (DATE_SUB(CURDATE(), INTERVAL 7 DAY), DATE_ADD(CURDATE(), INTERVAL 21 DAY), '2025-11');
SET @dashboard_id := LAST_INSERT_ID();

-- 3) Steps (match UI titles)
SET @bd_20 := (SELECT `business_day_id` FROM `Business_Day` WHERE `business_day`=20 LIMIT 1);
SET @bd_23 := (SELECT `business_day_id` FROM `Business_Day` WHERE `business_day`=23 LIMIT 1);
SET @bd_25 := (SELECT `business_day_id` FROM `Business_Day` WHERE `business_day`=25 LIMIT 1);
SET @bd_1  := (SELECT `business_day_id` FROM `Business_Day` WHERE `business_day`=1  LIMIT 1);
SET @bd_4  := (SELECT `business_day_id` FROM `Business_Day` WHERE `business_day`=4  LIMIT 1);

INSERT INTO `Step` (`dashboard_id`, `business_day_id`, `step_title`) VALUES
  (@dashboard_id, @bd_20, 'Populate Financials'),
  (@dashboard_id, @bd_23, 'First Review Complete'),
  (@dashboard_id, @bd_25, 'Second Review Complete'),
  (@dashboard_id, @bd_1,  'Flash JE Upload'),
  (@dashboard_id, @bd_4,  'Final JE Upload');

-- capture step ids
SET @step_populate := (SELECT `step_id` FROM `Step` WHERE `dashboard_id`=@dashboard_id AND `step_title`='Populate Financials' LIMIT 1);
SET @step_first    := (SELECT `step_id` FROM `Step` WHERE `dashboard_id`=@dashboard_id AND `step_title`='First Review Complete' LIMIT 1);
SET @step_second   := (SELECT `step_id` FROM `Step` WHERE `dashboard_id`=@dashboard_id AND `step_title`='Second Review Complete' LIMIT 1);
SET @step_flash    := (SELECT `step_id` FROM `Step` WHERE `dashboard_id`=@dashboard_id AND `step_title`='Flash JE Upload' LIMIT 1);
SET @step_final    := (SELECT `step_id` FROM `Step` WHERE `dashboard_id`=@dashboard_id AND `step_title`='Final JE Upload' LIMIT 1);

-- 4) Users (example team)
-- Passwords below are hashed with bcrypt. Plaintext (for demo):
--   atracy -> some_password_for_aidan
--   bgrbic -> some_password_for_bakir
--   adaniluc -> some_password_for_alex
--
-- Security Question for all: "What was the name of your first pet?"
-- Security Answer for all: "blah"
INSERT INTO `Users`
(`username`, `email`, `password`, `is_admin`, `first_name`, `last_name`, `ts_id`, `color_code`, `is_deleted`, `is_invited`, `security_question`, `security_answer_hash`)
VALUES
    ('atracy', 'aidan.tracy@u.boisestate.edu', '$2b$12$JSrJKA7xFs/0lqoMbFyCF.3txyoY3azN.fb0IZ4VywkgLfFRuK3Kq', 1, 'Aidan', 'Tracy',  NULL, '#2563EB', 0, 0, 'What was the name of your first pet?', '$2b$12$UnMdt7P/oL426zDvB0AXLOK7TPpJXGPikbStBukFDrTazW20rYvsC'),
    ('bgrbic', 'bakir.grbic@u.boisestate.edu', '$2b$12$7hOWLOeLVrrAUmYblRXel.Qbh6CdyRMirVNkd12/rUD8CGVzHJYbK', 1, 'Bakir', 'Grbic',  NULL, '#10B981', 0, 0, 'What was the name of your first pet?', '$2b$12$UnMdt7P/oL426zDvB0AXLOK7TPpJXGPikbStBukFDrTazW20rYvsC'),
    ('adaniluc', 'Alex.daniluc@u.boisestate.edu','$2b$12$DdD85RrhqdxwmHsg.aabLuGwKcJ6CCX0YBQ/LeTybmZG2nxsgJn5S', 0, 'Alex', 'Daniluc', NULL, '#A855F7', 0, 0, 'What was the name of your first pet?', '$2b$12$UnMdt7P/oL426zDvB0AXLOK7TPpJXGPikbStBukFDrTazW20rYvsC');

SET @user_aidan := (SELECT `user_id` FROM `Users` WHERE `username`='atracy'   LIMIT 1);
SET @user_bakir := (SELECT `user_id` FROM `Users` WHERE `username`='bgrbic'   LIMIT 1);
SET @user_alex  := (SELECT `user_id` FROM `Users` WHERE `username`='adaniluc' LIMIT 1);

-- Minimal audit/timestamps so foreign keys are happy (for each user)
INSERT INTO `Audit_Log` (`task_id`, `user_id`, `prev_state`, `new_state`, `table_type`, `table_id`)
VALUES (NULL, @user_aidan, NULL, 'created user', 'Users', @user_aidan);
SET @al_user_aidan := LAST_INSERT_ID();
INSERT INTO `Timestamps` (`audit_log_id`) VALUES (@al_user_aidan);
SET @ts_user_aidan := LAST_INSERT_ID();
UPDATE `Users` SET `ts_id`=@ts_user_aidan WHERE `user_id`=@user_aidan;

INSERT INTO `Audit_Log` (`task_id`, `user_id`, `prev_state`, `new_state`, `table_type`, `table_id`)
VALUES (NULL, @user_bakir, NULL, 'created user', 'Users', @user_bakir);
SET @al_user_bakir := LAST_INSERT_ID();
INSERT INTO `Timestamps` (`audit_log_id`) VALUES (@al_user_bakir);
SET @ts_user_bakir := LAST_INSERT_ID();
UPDATE `Users` SET `ts_id`=@ts_user_bakir WHERE `user_id`=@user_bakir;

INSERT INTO `Audit_Log` (`task_id`, `user_id`, `prev_state`, `new_state`, `table_type`, `table_id`)
VALUES (NULL, @user_alex, NULL, 'created user', 'Users', @user_alex);
SET @al_user_alex := LAST_INSERT_ID();
INSERT INTO `Timestamps` (`audit_log_id`) VALUES (@al_user_alex);
SET @ts_user_alex := LAST_INSERT_ID();
UPDATE `Users` SET `ts_id`=@ts_user_alex WHERE `user_id`=@user_alex;

-- set up invite keys
INSERT INTO `Invitation_Keys`
(`key_value`, `is_used`, `created_by_user_id`, `used_by_user_id`, `created_at`)
VALUES
    ('demo-key-alpha',   0, @user_aidan, NULL, NOW()),
    ('demo-key-beta',    0, @user_aidan, NULL, NOW()),
    ('demo-key-gamma',   0, @user_aidan, NULL, NOW());

-- 5) Status ids
SET @status_ns := (SELECT `status_id` FROM `Status` WHERE `status`='Not Started'  LIMIT 1);
SET @status_ip := (SELECT `status_id` FROM `Status` WHERE `status`='In Progress' LIMIT 1);
SET @status_sk := (SELECT `status_id` FROM `Status` WHERE `status`='Stuck'       LIMIT 1);
SET @status_dn := (SELECT `status_id` FROM `Status` WHERE `status`='Done'        LIMIT 1);

-- Helper pattern:
--   Create Audit_Log -> Timestamps -> Task (with notes) -> backfill Audit_Log.task_id

/* =========================
   6) Jordan’s Tasks (ordered as in TXT)
   ========================= */

-- Task 1
-- Send to Priya: Redwood Quarterly Invoicing (Due 11/25 → Step: Second Review Complete)
INSERT INTO Audit_Log (task_id, user_id, prev_state, new_state, table_type, table_id)
VALUES (NULL, @user_aidan, NULL, 'created task', 'Task', NULL);
SET @al_t1 := LAST_INSERT_ID();

INSERT INTO Timestamps (audit_log_id)
VALUES (@al_t1);
SET @ts_t1 := LAST_INSERT_ID();

INSERT INTO Task (due_date, ts_id, user_id, step_id, status_id, title, notes, is_deleted)
VALUES ('2025-11-25', @ts_t1, @user_aidan, @step_second, @status_dn,
        'Send to Priya: Redwood Quarterly Invoicing', NULL, 0);
SET @task_1 := LAST_INSERT_ID();

UPDATE Audit_Log
SET task_id = @task_1, table_id = @task_1
WHERE audit_log_id = @al_t1;


-- Task 2
-- Submission: Redwood Quarterly Invoicing (Due 12/22 → EXCLUDED: after 12/04)

-- Task 3
-- Final Review: Redwood Quarterly Invoicing (Due 11/22 → Step: First Review Complete)
INSERT INTO Audit_Log (task_id, user_id, prev_state, new_state, table_type, table_id)
VALUES (NULL, @user_bakir, NULL, 'created task', 'Task', NULL);
SET @al_t2 := LAST_INSERT_ID();

INSERT INTO Timestamps (audit_log_id)
VALUES (@al_t2);
SET @ts_t2 := LAST_INSERT_ID();

INSERT INTO Task (due_date, ts_id, user_id, step_id, status_id, title, notes, is_deleted)
VALUES ('2025-11-22', @ts_t2, @user_bakir, @step_first, @status_ip,
        'Final Review: Redwood Quarterly Invoicing', NULL, 0);
SET @task_2 := LAST_INSERT_ID();

UPDATE Audit_Log
SET task_id = @task_2, table_id = @task_2
WHERE audit_log_id = @al_t2;


-- Task 4
-- First Review: Redwood Quarterly Invoicing (Due 11/21 → Step: First Review Complete)
INSERT INTO Audit_Log (task_id, user_id, prev_state, new_state, table_type, table_id)
VALUES (NULL, @user_alex, NULL, 'created task', 'Task', NULL);
SET @al_t3 := LAST_INSERT_ID();

INSERT INTO Timestamps (audit_log_id)
VALUES (@al_t3);
SET @ts_t3 := LAST_INSERT_ID();

INSERT INTO Task (due_date, ts_id, user_id, step_id, status_id, title, notes, is_deleted)
VALUES ('2025-11-21', @ts_t3, @user_alex, @step_first, @status_ip,
        'First Review: Redwood Quarterly Invoicing', NULL, 0);
SET @task_3 := LAST_INSERT_ID();

UPDATE Audit_Log
SET task_id = @task_3, table_id = @task_3
WHERE audit_log_id = @al_t3;


-- Task 5
-- Submission: Stop Loss Review and Submission to Redwood - Over 100k (Due 11/15 → Populate Financials)
INSERT INTO Audit_Log (task_id, user_id, prev_state, new_state, table_type, table_id)
VALUES (NULL, @user_aidan, NULL, 'created task', 'Task', NULL);
SET @al_t4 := LAST_INSERT_ID();

INSERT INTO Timestamps (audit_log_id)
VALUES (@al_t4);
SET @ts_t4 := LAST_INSERT_ID();

INSERT INTO Task (due_date, ts_id, user_id, step_id, status_id, title, notes, is_deleted)
VALUES ('2025-11-15', @ts_t4, @user_aidan, @step_populate, @status_ip,
        'Submission: Stop Loss Review and Submission to Redwood - Over 100k', NULL, 0);
SET @task_4 := LAST_INSERT_ID();

UPDATE Audit_Log
SET task_id = @task_4, table_id = @task_4
WHERE audit_log_id = @al_t4;


-- Task 6
-- Second Review: Stop Loss Review and Submission to Redwood - Over 100k (Due 11/15 → Populate Financials)
INSERT INTO Audit_Log (task_id, user_id, prev_state, new_state, table_type, table_id)
VALUES (NULL, @user_bakir, NULL, 'created task', 'Task', NULL);
SET @al_t5 := LAST_INSERT_ID();

INSERT INTO Timestamps (audit_log_id)
VALUES (@al_t5);
SET @ts_t5 := LAST_INSERT_ID();

INSERT INTO Task (due_date, ts_id, user_id, step_id, status_id, title, notes, is_deleted)
VALUES ('2025-11-15', @ts_t5, @user_bakir, @step_populate, @status_ip,
        'Second Review: Stop Loss Review and Submission to Redwood - Over 100k', NULL, 0);
SET @task_5 := LAST_INSERT_ID();

UPDATE Audit_Log
SET task_id = @task_5, table_id = @task_5
WHERE audit_log_id = @al_t5;


-- Task 7
-- First Review: Stop Loss Review and Submission to Redwood - Over 100k (Due 11/15 → Populate Financials)
INSERT INTO Audit_Log (task_id, user_id, prev_state, new_state, table_type, table_id)
VALUES (NULL, @user_alex, NULL, 'created task', 'Task', NULL);
SET @al_t6 := LAST_INSERT_ID();

INSERT INTO Timestamps (audit_log_id)
VALUES (@al_t6);
SET @ts_t6 := LAST_INSERT_ID();

INSERT INTO Task (due_date, ts_id, user_id, step_id, status_id, title, notes, is_deleted)
VALUES ('2025-11-15', @ts_t6, @user_alex, @step_populate, @status_ip,
        'First Review: Stop Loss Review and Submission to Redwood - Over 100k', NULL, 0);
SET @task_6 := LAST_INSERT_ID();

UPDATE Audit_Log
SET task_id = @task_6, table_id = @task_6
WHERE audit_log_id = @al_t6;

-- Task 8
-- Update to ELC on P4P and LOB Surplus (Due 12/01 → Flash JE Upload)
INSERT INTO Audit_Log (task_id, user_id, prev_state, new_state, table_type, table_id)
VALUES (NULL, @user_aidan, NULL, 'created task', 'Task', NULL);
SET @al_t7 := LAST_INSERT_ID();

INSERT INTO Timestamps (audit_log_id)
VALUES (@al_t7);
SET @ts_t7 := LAST_INSERT_ID();

INSERT INTO Task (due_date, ts_id, user_id, step_id, status_id, title, notes, is_deleted)
VALUES ('2025-12-01', @ts_t7, @user_aidan, @step_flash, @status_ns,
        'Update to ELC on P4P and LOB Surplus', NULL, 0);
SET @task_7 := LAST_INSERT_ID();

UPDATE Audit_Log
SET task_id = @task_7, table_id = @task_7
WHERE audit_log_id = @al_t7;


-- Task 9
-- Forecast JE Upload (Remaining Forecast months and current month actuals) (Due 12/01 → Flash JE Upload)
INSERT INTO Audit_Log (task_id, user_id, prev_state, new_state, table_type, table_id)
VALUES (NULL, @user_bakir, NULL, 'created task', 'Task', NULL);
SET @al_t8 := LAST_INSERT_ID();

INSERT INTO Timestamps (audit_log_id)
VALUES (@al_t8);
SET @ts_t8 := LAST_INSERT_ID();

INSERT INTO Task (due_date, ts_id, user_id, step_id, status_id, title, notes, is_deleted)
VALUES ('2025-12-01', @ts_t8, @user_bakir, @step_flash, @status_ns,
        'Forecast JE Upload (Remaining Forecast months and current month actuals)', NULL, 0);
SET @task_8 := LAST_INSERT_ID();

UPDATE Audit_Log
SET task_id = @task_8, table_id = @task_8
WHERE audit_log_id = @al_t8;


-- Task 10
-- Sign off on JE backup (Due 11/16 → Populate Financials)
INSERT INTO Audit_Log (task_id, user_id, prev_state, new_state, table_type, table_id)
VALUES (NULL, @user_alex, NULL, 'created task', 'Task', NULL);
SET @al_t9 := LAST_INSERT_ID();

INSERT INTO Timestamps (audit_log_id)
VALUES (@al_t9);
SET @ts_t9 := LAST_INSERT_ID();

INSERT INTO Task (due_date, ts_id, user_id, step_id, status_id, title, notes, is_deleted)
VALUES ('2025-11-16', @ts_t9, @user_alex, @step_populate, @status_dn,
        'Sign off on JE backup', NULL, 0);
SET @task_9 := LAST_INSERT_ID();

UPDATE Audit_Log
SET task_id = @task_9, table_id = @task_9
WHERE audit_log_id = @al_t9;


-- Task 11
-- Populate financial statements - Health Plan (Due 11/20 → First Review Complete)
INSERT INTO Audit_Log (task_id, user_id, prev_state, new_state, table_type, table_id)
VALUES (NULL, @user_aidan, NULL, 'created task', 'Task', NULL);
SET @al_t10 := LAST_INSERT_ID();

INSERT INTO Timestamps (audit_log_id)
VALUES (@al_t10);
SET @ts_t10 := LAST_INSERT_ID();

INSERT INTO Task (due_date, ts_id, user_id, step_id, status_id, title, notes, is_deleted)
VALUES ('2025-11-20', @ts_t10, @user_aidan, @step_first, @status_ns,
        'Populate financial statements - Health Plan', NULL, 0);
SET @task_10 := LAST_INSERT_ID();

UPDATE Audit_Log
SET task_id = @task_10, table_id = @task_10
WHERE audit_log_id = @al_t10;


-- Task 12
-- Populate financial statements - EE Plan (Due 11/20 → First Review Complete)
INSERT INTO Audit_Log (task_id, user_id, prev_state, new_state, table_type, table_id)
VALUES (NULL, @user_bakir, NULL, 'created task', 'Task', NULL);
SET @al_t11 := LAST_INSERT_ID();

INSERT INTO Timestamps (audit_log_id)
VALUES (@al_t11);
SET @ts_t11 := LAST_INSERT_ID();

INSERT INTO Task (due_date, ts_id, user_id, step_id, status_id, title, notes, is_deleted)
VALUES ('2025-11-20', @ts_t11, @user_bakir, @step_first, @status_ns,
        'Populate financial statements - EE Plan', NULL, 0);
SET @task_11 := LAST_INSERT_ID();

UPDATE Audit_Log
SET task_id = @task_11, table_id = @task_11
WHERE audit_log_id = @al_t11;


-- Task 13
-- Populate financial statements - Health Plan & EE Plan (Due 11/20 → First Review Complete)
INSERT INTO Audit_Log (task_id, user_id, prev_state, new_state, table_type, table_id)
VALUES (NULL, @user_alex, NULL, 'created task', 'Task', NULL);
SET @al_t12 := LAST_INSERT_ID();

INSERT INTO Timestamps (audit_log_id)
VALUES (@al_t12);
SET @ts_t12 := LAST_INSERT_ID();

INSERT INTO Task (due_date, ts_id, user_id, step_id, status_id, title, notes, is_deleted)
VALUES ('2025-11-20', @ts_t12, @user_alex, @step_first, @status_ns,
        'Populate financial statements - Health Plan & EE Plan', NULL, 0);
SET @task_12 := LAST_INSERT_ID();

UPDATE Audit_Log
SET task_id = @task_12, table_id = @task_12
WHERE audit_log_id = @al_t12;

-- Task 14
-- Prepare: Redwood Quarterly Invoicing (Due 11/21 → First Review Complete)
INSERT INTO Audit_Log (task_id, user_id, prev_state, new_state, table_type, table_id)
VALUES (NULL, @user_aidan, NULL, 'created task', 'Task', NULL);
SET @al_t13 := LAST_INSERT_ID();

INSERT INTO Timestamps (audit_log_id)
VALUES (@al_t13);
SET @ts_t13 := LAST_INSERT_ID();

INSERT INTO Task (due_date, ts_id, user_id, step_id, status_id, title, notes, is_deleted)
VALUES ('2025-11-21', @ts_t13, @user_aidan, @step_first, @status_ns,
        'Prepare: Redwood Quarterly Invoicing', NULL, 0);
SET @task_13 := LAST_INSERT_ID();

UPDATE Audit_Log
SET task_id = @task_13, table_id = @task_13
WHERE audit_log_id = @al_t13;


-- Task 15
-- IBNR's Reviewed/Updated (Due 11/23 → Second Review Complete)
INSERT INTO Audit_Log (task_id, user_id, prev_state, new_state, table_type, table_id)
VALUES (NULL, @user_bakir, NULL, 'created task', 'Task', NULL);
SET @al_t14 := LAST_INSERT_ID();

INSERT INTO Timestamps (audit_log_id)
VALUES (@al_t14);
SET @ts_t14 := LAST_INSERT_ID();

INSERT INTO Task (due_date, ts_id, user_id, step_id, status_id, title, notes, is_deleted)
VALUES ('2025-11-23', @ts_t14, @user_bakir, @step_second, @status_ip,
        'IBNR''s Reviewed/Updated', NULL, 0);
SET @task_14 := LAST_INSERT_ID();

UPDATE Audit_Log
SET task_id = @task_14, table_id = @task_14
WHERE audit_log_id = @al_t14;


-- Task 16
-- IBNR's Reviewed/Updated - Bluewater Advantage (Due 11/23 → Second Review Complete)
INSERT INTO Audit_Log (task_id, user_id, prev_state, new_state, table_type, table_id)
VALUES (NULL, @user_alex, NULL, 'created task', 'Task', NULL);
SET @al_t15 := LAST_INSERT_ID();

INSERT INTO Timestamps (audit_log_id)
VALUES (@al_t15);
SET @ts_t15 := LAST_INSERT_ID();

INSERT INTO Task (due_date, ts_id, user_id, step_id, status_id, title, notes, is_deleted)
VALUES ('2025-11-23', @ts_t15, @user_alex, @step_second, @status_ip,
        'IBNR''s Reviewed/Updated - Bluewater Advantage', NULL, 0);
SET @task_15 := LAST_INSERT_ID();

UPDATE Audit_Log
SET task_id = @task_15, table_id = @task_15
WHERE audit_log_id = @al_t15;


-- Task 17
-- IBNR's Reviewed/Updated - CarePlus (Due 11/23 → Second Review Complete)
INSERT INTO Audit_Log (task_id, user_id, prev_state, new_state, table_type, table_id)
VALUES (NULL, @user_aidan, NULL, 'created task', 'Task', NULL);
SET @al_t16 := LAST_INSERT_ID();

INSERT INTO Timestamps (audit_log_id)
VALUES (@al_t16);
SET @ts_t16 := LAST_INSERT_ID();

INSERT INTO Task (due_date, ts_id, user_id, step_id, status_id, title, notes, is_deleted)
VALUES ('2025-11-23', @ts_t16, @user_aidan, @step_second, @status_ip,
        'IBNR''s Reviewed/Updated - CarePlus', NULL, 0);
SET @task_16 := LAST_INSERT_ID();

UPDATE Audit_Log
SET task_id = @task_16, table_id = @task_16
WHERE audit_log_id = @al_t16;


-- Task 18
-- IBNR's Reviewed/Updated - VHC (Due 11/23 → Second Review Complete)
INSERT INTO Audit_Log (task_id, user_id, prev_state, new_state, table_type, table_id)
VALUES (NULL, @user_bakir, NULL, 'created task', 'Task', NULL);
SET @al_t17 := LAST_INSERT_ID();

INSERT INTO Timestamps (audit_log_id)
VALUES (@al_t17);
SET @ts_t17 := LAST_INSERT_ID();

INSERT INTO Task (due_date, ts_id, user_id, step_id, status_id, title, notes, is_deleted)
VALUES ('2025-11-23', @ts_t17, @user_bakir, @step_second, @status_ip,
        'IBNR''s Reviewed/Updated - VHC', NULL, 0);
SET @task_17 := LAST_INSERT_ID();

UPDATE Audit_Log
SET task_id = @task_17, table_id = @task_17
WHERE audit_log_id = @al_t17;


-- Task 19
-- IBNR's Reviewed/Updated - Connect (Due 11/23 → Second Review Complete)
INSERT INTO Audit_Log (task_id, user_id, prev_state, new_state, table_type, table_id)
VALUES (NULL, @user_alex, NULL, 'created task', 'Task', NULL);
SET @al_t18 := LAST_INSERT_ID();

INSERT INTO Timestamps (audit_log_id)
VALUES (@al_t18);
SET @ts_t18 := LAST_INSERT_ID();

INSERT INTO Task (due_date, ts_id, user_id, step_id, status_id, title, notes, is_deleted)
VALUES ('2025-11-23', @ts_t18, @user_alex, @step_second, @status_ip,
        'IBNR''s Reviewed/Updated - Connect', NULL, 0);
SET @task_18 := LAST_INSERT_ID();

UPDATE Audit_Log
SET task_id = @task_18, table_id = @task_18
WHERE audit_log_id = @al_t18;


-- Task 20
-- IBNR's Reviewed/Updated - Cascade (Due 11/23 → Second Review Complete)
INSERT INTO Audit_Log (task_id, user_id, prev_state, new_state, table_type, table_id)
VALUES (NULL, @user_aidan, NULL, 'created task', 'Task', NULL);
SET @al_t19 := LAST_INSERT_ID();

INSERT INTO Timestamps (audit_log_id)
VALUES (@al_t19);
SET @ts_t19 := LAST_INSERT_ID();

INSERT INTO Task (due_date, ts_id, user_id, step_id, status_id, title, notes, is_deleted)
VALUES ('2025-11-23', @ts_t19, @user_aidan, @step_second, @status_ip,
        'IBNR''s Reviewed/Updated - Cascade', NULL, 0);
SET @task_19 := LAST_INSERT_ID();

UPDATE Audit_Log
SET task_id = @task_19, table_id = @task_19
WHERE audit_log_id = @al_t19;


-- Task 21
-- IBNR's Reviewed/Updated - Unity (Due 11/23 → Second Review Complete)
INSERT INTO Audit_Log (task_id, user_id, prev_state, new_state, table_type, table_id)
VALUES (NULL, @user_bakir, NULL, 'created task', 'Task', NULL);
SET @al_t20 := LAST_INSERT_ID();

INSERT INTO Timestamps (audit_log_id)
VALUES (@al_t20);
SET @ts_t20 := LAST_INSERT_ID();

INSERT INTO Task (due_date, ts_id, user_id, step_id, status_id, title, notes, is_deleted)
VALUES ('2025-11-23', @ts_t20, @user_bakir, @step_second, @status_ip,
        'IBNR''s Reviewed/Updated - Unity', NULL, 0);
SET @task_20 := LAST_INSERT_ID();

UPDATE Audit_Log
SET task_id = @task_20, table_id = @task_20
WHERE audit_log_id = @al_t20;

-- Task 22
-- IBNR's Reviewed/Updated - AHS (Due 11/23 → Second Review Complete)
INSERT INTO Audit_Log (task_id, user_id, prev_state, new_state, table_type, table_id)
VALUES (NULL, @user_alex, NULL, 'created task', 'Task', NULL);
SET @al_t21 := LAST_INSERT_ID();

INSERT INTO Timestamps (audit_log_id)
VALUES (@al_t21);
SET @ts_t21 := LAST_INSERT_ID();

INSERT INTO Task (due_date, ts_id, user_id, step_id, status_id, title, notes, is_deleted)
VALUES ('2025-11-23', @ts_t21, @user_alex, @step_second, @status_ip,
        'IBNR''s Reviewed/Updated - AHS', NULL, 0);
SET @task_21 := LAST_INSERT_ID();

UPDATE Audit_Log
SET task_id = @task_21, table_id = @task_21
WHERE audit_log_id = @al_t21;


-- Task 23
-- IBNR's Reviewed/Updated - WH (Due 11/23 → Second Review Complete)
INSERT INTO Audit_Log (task_id, user_id, prev_state, new_state, table_type, table_id)
VALUES (NULL, @user_aidan, NULL, 'created task', 'Task', NULL);
SET @al_t22 := LAST_INSERT_ID();

INSERT INTO Timestamps (audit_log_id)
VALUES (@al_t22);
SET @ts_t22 := LAST_INSERT_ID();

INSERT INTO Task (due_date, ts_id, user_id, step_id, status_id, title, notes, is_deleted)
VALUES ('2025-11-23', @ts_t22, @user_aidan, @step_second, @status_ip,
        'IBNR''s Reviewed/Updated - WH', NULL, 0);
SET @task_22 := LAST_INSERT_ID();

UPDATE Audit_Log
SET task_id = @task_22, table_id = @task_22
WHERE audit_log_id = @al_t22;


-- Task 24
-- Stop Loss Updated in Financials (Due 11/23 → Second Review Complete)
INSERT INTO Audit_Log (task_id, user_id, prev_state, new_state, table_type, table_id)
VALUES (NULL, @user_bakir, NULL, 'created task', 'Task', NULL);
SET @al_t23 := LAST_INSERT_ID();

INSERT INTO Timestamps (audit_log_id)
VALUES (@al_t23);
SET @ts_t23 := LAST_INSERT_ID();

INSERT INTO Task (due_date, ts_id, user_id, step_id, status_id, title, notes, is_deleted)
VALUES ('2025-11-23', @ts_t23, @user_bakir, @step_second, @status_ns,
        'Stop Loss Updated in Financials', NULL, 0);
SET @task_23 := LAST_INSERT_ID();

UPDATE Audit_Log
SET task_id = @task_23, table_id = @task_23
WHERE audit_log_id = @al_t23;


-- Task 25
-- Review variance analysis file (Due 12/09 → EXCLUDED: after 12/04)
-- (Skipping)


-- Task 26
-- Health Partners Financials by LOB sent to Karen Bishop and Diane Porter (Due 11/12 → Populate Financials)
INSERT INTO Audit_Log (task_id, user_id, prev_state, new_state, table_type, table_id)
VALUES (NULL, @user_alex, NULL, 'created task', 'Task', NULL);
SET @al_t24 := LAST_INSERT_ID();

INSERT INTO Timestamps (audit_log_id)
VALUES (@al_t24);
SET @ts_t24 := LAST_INSERT_ID();

INSERT INTO Task (due_date, ts_id, user_id, step_id, status_id, title, notes, is_deleted)
VALUES ('2025-11-12', @ts_t24, @user_alex, @step_populate, @status_ns,
        'Health Partners Financials by LOB sent to Karen Bishop and Diane Porter', NULL, 0);
SET @task_24 := LAST_INSERT_ID();

UPDATE Audit_Log
SET task_id = @task_24, table_id = @task_24
WHERE audit_log_id = @al_t24;


-- Task 27
-- Capitated Payment Reconciliation (Due 11/14 → Populate Financials)
INSERT INTO Audit_Log (task_id, user_id, prev_state, new_state, table_type, table_id)
VALUES (NULL, @user_aidan, NULL, 'created task', 'Task', NULL);
SET @al_t25 := LAST_INSERT_ID();

INSERT INTO Timestamps (audit_log_id)
VALUES (@al_t25);
SET @ts_t25 := LAST_INSERT_ID();

INSERT INTO Task (due_date, ts_id, user_id, step_id, status_id, title, notes, is_deleted)
VALUES ('2025-11-14', @ts_t25, @user_aidan, @step_populate, @status_ns,
        'Capitated Payment Reconciliation', 'Once we receive updated Alternative payment arrangement report (APA) in 4i and financials are rolled forward', 0);
SET @task_25 := LAST_INSERT_ID();

UPDATE Audit_Log
SET task_id = @task_25, table_id = @task_25
WHERE audit_log_id = @al_t25;


-- Task 28
-- Review Board Pack (Due 11/10 → Populate Financials)
INSERT INTO Audit_Log (task_id, user_id, prev_state, new_state, table_type, table_id)
VALUES (NULL, @user_bakir, NULL, 'created task', 'Task', NULL);
SET @al_t26 := LAST_INSERT_ID();

INSERT INTO Timestamps (audit_log_id)
VALUES (@al_t26);
SET @ts_t26 := LAST_INSERT_ID();

INSERT INTO Task (due_date, ts_id, user_id, step_id, status_id, title, notes, is_deleted)
VALUES ('2025-11-10', @ts_t26, @user_bakir, @step_populate, @status_ip,
        'Review Board Pack', NULL, 0);
SET @task_26 := LAST_INSERT_ID();

UPDATE Audit_Log
SET task_id = @task_26, table_id = @task_26
WHERE audit_log_id = @al_t26;


-- Task 29
-- Prepare committee/board reports (Due 01/10/2026 → EXCLUDED)
-- (Skipping)


-- Task 30
-- 1099 Final Review (Due 01/19/2026 → EXCLUDED)
-- (Skipping)


-- Task 31
-- Bluewater Advantage - data files (Due 12/08 → EXCLUDED: after cutoff)
-- (Skipping)


-- Task 32
-- Bluewater CarePlus - data files (Due 11/15 → Populate Financials)
INSERT INTO Audit_Log (task_id, user_id, prev_state, new_state, table_type, table_id)
VALUES (NULL, @user_alex, NULL, 'created task', 'Task', NULL);
SET @al_t27 := LAST_INSERT_ID();

INSERT INTO Timestamps (audit_log_id)
VALUES (@al_t27);
SET @ts_t27 := LAST_INSERT_ID();

INSERT INTO Task (due_date, ts_id, user_id, step_id, status_id, title, notes, is_deleted)
VALUES ('2025-11-15', @ts_t27, @user_alex, @step_populate, @status_ns,
        'Bluewater CarePlus - data files', NULL, 0);
SET @task_27 := LAST_INSERT_ID();

UPDATE Audit_Log
SET task_id = @task_27, table_id = @task_27
WHERE audit_log_id = @al_t27;


-- Task 33
-- WH Summary Files (Due 11/15 → Populate Financials)
INSERT INTO Audit_Log (task_id, user_id, prev_state, new_state, table_type, table_id)
VALUES (NULL, @user_aidan, NULL, 'created task', 'Task', NULL);
SET @al_t28 := LAST_INSERT_ID();

INSERT INTO Timestamps (audit_log_id)
VALUES (@al_t28);
SET @ts_t28 := LAST_INSERT_ID();

INSERT INTO Task (due_date, ts_id, user_id, step_id, status_id, title, notes, is_deleted)
VALUES ('2025-11-15', @ts_t28, @user_aidan, @step_populate, @status_ns,
        'WH Summary Files', NULL, 0);
SET @task_28 := LAST_INSERT_ID();

UPDATE Audit_Log
SET task_id = @task_28, table_id = @task_28
WHERE audit_log_id = @al_t28;


-- Task 34
-- WH Data files - AHS portion (Due 11/15 → Populate Financials)
INSERT INTO Audit_Log (task_id, user_id, prev_state, new_state, table_type, table_id)
VALUES (NULL, @user_bakir, NULL, 'created task', 'Task', NULL);
SET @al_t29 := LAST_INSERT_ID();

INSERT INTO Timestamps (audit_log_id)
VALUES (@al_t29);
SET @ts_t29 := LAST_INSERT_ID();

INSERT INTO Task (due_date, ts_id, user_id, step_id, status_id, title, notes, is_deleted)
VALUES ('2025-11-15', @ts_t29, @user_bakir, @step_populate, @status_ns,
        'WH Data files - AHS portion', NULL, 0);
SET @task_29 := LAST_INSERT_ID();

UPDATE Audit_Log
SET task_id = @task_29, table_id = @task_29
WHERE audit_log_id = @al_t29;


-- Task 35
-- Unity Focus Summary Files (Due 11/15 → Populate Financials)
INSERT INTO Audit_Log (task_id, user_id, prev_state, new_state, table_type, table_id)
VALUES (NULL, @user_alex, NULL, 'created task', 'Task', NULL);
SET @al_t30 := LAST_INSERT_ID();

INSERT INTO Timestamps (audit_log_id)
VALUES (@al_t30);
SET @ts_t30 := LAST_INSERT_ID();

INSERT INTO Task (due_date, ts_id, user_id, step_id, status_id, title, notes, is_deleted)
VALUES ('2025-11-15', @ts_t30, @user_alex, @step_populate, @status_ns,
        'Unity Focus Summary Files', NULL, 0);
SET @task_30 := LAST_INSERT_ID();

UPDATE Audit_Log
SET task_id = @task_30, table_id = @task_30
WHERE audit_log_id = @al_t30;


-- Task 36
-- Unity Focus Data Files - AHS portion (Due 11/15 → Populate Financials)
INSERT INTO Audit_Log (task_id, user_id, prev_state, new_state, table_type, table_id)
VALUES (NULL, @user_aidan, NULL, 'created task', 'Task', NULL);
SET @al_t31 := LAST_INSERT_ID();

INSERT INTO Timestamps (audit_log_id)
VALUES (@al_t31);
SET @ts_t31 := LAST_INSERT_ID();

INSERT INTO Task (due_date, ts_id, user_id, step_id, status_id, title, notes, is_deleted)
VALUES ('2025-11-15', @ts_t31, @user_aidan, @step_populate, @status_ns,
        'Unity Focus Data Files - AHS portion', NULL, 0);
SET @task_31 := LAST_INSERT_ID();

UPDATE Audit_Log
SET task_id = @task_31, table_id = @task_31
WHERE audit_log_id = @al_t31;


-- Task 37
-- AHS Employee Plan 2024 - Marcus's Report (Due 11/15 → Populate Financials)
INSERT INTO Audit_Log (task_id, user_id, prev_state, new_state, table_type, table_id)
VALUES (NULL, @user_bakir, NULL, 'created task', 'Task', NULL);
SET @al_t32 := LAST_INSERT_ID();

INSERT INTO Timestamps (audit_log_id)
VALUES (@al_t32);
SET @ts_t32 := LAST_INSERT_ID();

INSERT INTO Task (due_date, ts_id, user_id, step_id, status_id, title, notes, is_deleted)
VALUES ('2025-11-15', @ts_t32, @user_bakir, @step_populate, @status_ns,
        'AHS Employee Plan 2024 - Marcus''s Report', NULL, 0);
SET @task_32 := LAST_INSERT_ID();

UPDATE Audit_Log
SET task_id = @task_32, table_id = @task_32
WHERE audit_log_id = @al_t32;


-- Task 38
-- AHS Employee Plan 2024 - Data Files for AHS (Due 11/15 → Populate Financials)
INSERT INTO Audit_Log (task_id, user_id, prev_state, new_state, table_type, table_id)
VALUES (NULL, @user_alex, NULL, 'created task', 'Task', NULL);
SET @al_t33 := LAST_INSERT_ID();

INSERT INTO Timestamps (audit_log_id)
VALUES (@al_t33);
SET @ts_t33 := LAST_INSERT_ID();

INSERT INTO Task (due_date, ts_id, user_id, step_id, status_id, title, notes, is_deleted)
VALUES ('2025-11-15', @ts_t33, @user_alex, @step_populate, @status_ns,
        'AHS Employee Plan 2024 - Data Files for AHS', NULL, 0);
SET @task_33 := LAST_INSERT_ID();

UPDATE Audit_Log
SET task_id = @task_33, table_id = @task_33
WHERE audit_log_id = @al_t33;


-- Task 39
-- Unity Senior (upside only) (Due 11/15 → Populate Financials)
INSERT INTO Audit_Log (task_id, user_id, prev_state, new_state, table_type, table_id)
VALUES (NULL, @user_aidan, NULL, 'created task', 'Task', NULL);
SET @al_t34 := LAST_INSERT_ID();

INSERT INTO Timestamps (audit_log_id)
VALUES (@al_t34);
SET @ts_t34 := LAST_INSERT_ID();

INSERT INTO Task (due_date, ts_id, user_id, step_id, status_id, title, notes, is_deleted)
VALUES ('2025-11-15', @ts_t34, @user_aidan, @step_populate, @status_ns,
        'Unity Senior (upside only)', NULL, 0);
SET @task_34 := LAST_INSERT_ID();

UPDATE Audit_Log
SET task_id = @task_34, table_id = @task_34
WHERE audit_log_id = @al_t34;


-- Task 40
-- ACO Connect - CCLF Files (data files AHS) (Due 11/15 → Populate Financials)
INSERT INTO Audit_Log (task_id, user_id, prev_state, new_state, table_type, table_id)
VALUES (NULL, @user_bakir, NULL, 'created task', 'Task', NULL);
SET @al_t35 := LAST_INSERT_ID();

INSERT INTO Timestamps (audit_log_id)
VALUES (@al_t35);
SET @ts_t35 := LAST_INSERT_ID();

INSERT INTO Task (due_date, ts_id, user_id, step_id, status_id, title, notes, is_deleted)
VALUES ('2025-11-15', @ts_t35, @user_bakir, @step_populate, @status_ns,
        'ACO Connect - CCLF Files (data files AHS)', NULL, 0);
SET @task_35 := LAST_INSERT_ID();

UPDATE Audit_Log
SET task_id = @task_35, table_id = @task_35
WHERE audit_log_id = @al_t35;


-- Task 41
-- Update Triangles - Cascadia MA (Summary files) (Due 11/12 → Populate Financials)
INSERT INTO Audit_Log (task_id, user_id, prev_state, new_state, table_type, table_id)
VALUES (NULL, @user_alex, NULL, 'created task', 'Task', NULL);
SET @al_t36 := LAST_INSERT_ID();

INSERT INTO Timestamps (audit_log_id)
VALUES (@al_t36);
SET @ts_t36 := LAST_INSERT_ID();

INSERT INTO Task (due_date, ts_id, user_id, step_id, status_id, title, notes, is_deleted)
VALUES ('2025-11-12', @ts_t36, @user_alex, @step_populate, @status_ns,
        'Update Triangles - Cascadia MA (Summary files)', NULL, 0);
SET @task_36 := LAST_INSERT_ID();

UPDATE Audit_Log
SET task_id = @task_36, table_id = @task_36
WHERE audit_log_id = @al_t36;


-- Task 42
-- Update Triangles - Cascadia Large (Summary files) (Due 11/12 → Populate Financials)
INSERT INTO Audit_Log (task_id, user_id, prev_state, new_state, table_type, table_id)
VALUES (NULL, @user_aidan, NULL, 'created task', 'Task', NULL);
SET @al_t37 := LAST_INSERT_ID();

INSERT INTO Timestamps (audit_log_id)
VALUES (@al_t37);
SET @ts_t37 := LAST_INSERT_ID();

INSERT INTO Task (due_date, ts_id, user_id, step_id, status_id, title, notes, is_deleted)
VALUES ('2025-11-12', @ts_t37, @user_aidan, @step_populate, @status_ns,
        'Update Triangles - Cascadia Large (Summary files)', NULL, 0);
SET @task_37 := LAST_INSERT_ID();

UPDATE Audit_Log
SET task_id = @task_37, table_id = @task_37
WHERE audit_log_id = @al_t37;


-- Task 43
-- Update Triangles - Cascadia Small (Summary files) (Due 11/12 → Populate Financials)
INSERT INTO Audit_Log (task_id, user_id, prev_state, new_state, table_type, table_id)
VALUES (NULL, @user_bakir, NULL, 'created task', 'Task', NULL);
SET @al_t38 := LAST_INSERT_ID();

INSERT INTO Timestamps (audit_log_id)
VALUES (@al_t38);
SET @ts_t38 := LAST_INSERT_ID();

INSERT INTO Task (due_date, ts_id, user_id, step_id, status_id, title, notes, is_deleted)
VALUES ('2025-11-12', @ts_t38, @user_bakir, @step_populate, @status_ns,
        'Update Triangles - Cascadia Small (Summary files)', NULL, 0);
SET @task_38 := LAST_INSERT_ID();

UPDATE Audit_Log
SET task_id = @task_38, table_id = @task_38
WHERE audit_log_id = @al_t38;


-- Task 44
-- Prepare Board Pack: Paula - Prep (Due 11/12 → Populate Financials)
INSERT INTO Audit_Log (task_id, user_id, prev_state, new_state, table_type, table_id)
VALUES (NULL, @user_alex, NULL, 'created task', 'Task', NULL);
SET @al_t39 := LAST_INSERT_ID();

INSERT INTO Timestamps (audit_log_id)
VALUES (@al_t39);
SET @ts_t39 := LAST_INSERT_ID();

INSERT INTO Task (due_date, ts_id, user_id, step_id, status_id, title, notes, is_deleted)
VALUES ('2025-11-12', @ts_t39, @user_alex, @step_populate, @status_ns,
        'Prepare Board Pack: Paula - Prep', NULL, 0);
SET @task_39 := LAST_INSERT_ID();

UPDATE Audit_Log
SET task_id = @task_39, table_id = @task_39
WHERE audit_log_id = @al_t39;


-- Task 45
-- Prepare Board Pack: Nadia Review (Due 11/12 → Populate Financials)
INSERT INTO Audit_Log (task_id, user_id, prev_state, new_state, table_type, table_id)
VALUES (NULL, @user_aidan, NULL, 'created task', 'Task', NULL);
SET @al_t40 := LAST_INSERT_ID();

INSERT INTO Timestamps (audit_log_id)
VALUES (@al_t40);
SET @ts_t40 := LAST_INSERT_ID();

INSERT INTO Task (due_date, ts_id, user_id, step_id, status_id, title, notes, is_deleted)
VALUES ('2025-11-12', @ts_t40, @user_aidan, @step_populate, @status_ip,
        'Prepare Board Pack: Nadia Review', NULL, 0);
SET @task_40 := LAST_INSERT_ID();

UPDATE Audit_Log
SET task_id = @task_40, table_id = @task_40
WHERE audit_log_id = @al_t40;


-- Task 46
-- Prepare Board Pack: Jordan - final review (Due 11/12 → Populate Financials)
INSERT INTO Audit_Log (task_id, user_id, prev_state, new_state, table_type, table_id)
VALUES (NULL, @user_bakir, NULL, 'created task', 'Task', NULL);
SET @al_t41 := LAST_INSERT_ID();

INSERT INTO Timestamps (audit_log_id)
VALUES (@al_t41);
SET @ts_t41 := LAST_INSERT_ID();

INSERT INTO Task (due_date, ts_id, user_id, step_id, status_id, title, notes, is_deleted)
VALUES ('2025-11-12', @ts_t41, @user_bakir, @step_populate, @status_ip,
        'Prepare Board Pack: Jordan - final review', NULL, 0);
SET @task_41 := LAST_INSERT_ID();

UPDATE Audit_Log
SET task_id = @task_41, table_id = @task_41
WHERE audit_log_id = @al_t41;


-- Task 47
-- Prepare Board Pack: Paula - save files in AHS shared folder and… (Due 11/12 → Populate Financials)
INSERT INTO Audit_Log (task_id, user_id, prev_state, new_state, table_type, table_id)
VALUES (NULL, @user_alex, NULL, 'created task', 'Task', NULL);
SET @al_t42 := LAST_INSERT_ID();

INSERT INTO Timestamps (audit_log_id)
VALUES (@al_t42);
SET @ts_t42 := LAST_INSERT_ID();

INSERT INTO Task (due_date, ts_id, user_id, step_id, status_id, title, notes, is_deleted)
VALUES ('2025-11-12', @ts_t42, @user_alex, @step_populate, @status_ns,
        'Prepare Board Pack: Paula - save files in AHS shared folder and', NULL, 0);
SET @task_42 := LAST_INSERT_ID();

UPDATE Audit_Log
SET task_id = @task_42, table_id = @task_42
WHERE audit_log_id = @al_t42;


-- Task 48
-- Update Vantage Monthly Memo Stats (Due 12/03 → Final JE Upload)
INSERT INTO Audit_Log (task_id, user_id, prev_state, new_state, table_type, table_id)
VALUES (NULL, @user_aidan, NULL, 'created task', 'Task', NULL);
SET @al_t43 := LAST_INSERT_ID();

INSERT INTO Timestamps (audit_log_id)
VALUES (@al_t43);
SET @ts_t43 := LAST_INSERT_ID();

INSERT INTO Task (due_date, ts_id, user_id, step_id, status_id, title, notes, is_deleted)
VALUES ('2025-12-03', @ts_t43, @user_aidan, @step_final, @status_ns,
        'Update Vantage Monthly Memo Stats', NULL, 0);
SET @task_43 := LAST_INSERT_ID();

UPDATE Audit_Log
SET task_id = @task_43, table_id = @task_43
WHERE audit_log_id = @al_t43;


-- Task 49
-- Update AHP Portfolio Overview (Due 12/06 → EXCLUDED: after cutoff)
-- Skipping


-- Task 50
-- Update Monthly Growth and Retention file (Due 11/11 → Populate Financials)
INSERT INTO Audit_Log (task_id, user_id, prev_state, new_state, table_type, table_id)
VALUES (NULL, @user_bakir, NULL, 'created task', 'Task', NULL);
SET @al_t44 := LAST_INSERT_ID();

INSERT INTO Timestamps (audit_log_id)
VALUES (@al_t44);
SET @ts_t44 := LAST_INSERT_ID();

INSERT INTO Task (due_date, ts_id, user_id, step_id, status_id, title, notes, is_deleted)
VALUES ('2025-11-11', @ts_t44, @user_bakir, @step_populate, @status_ns,
        'Update Monthly Growth and Retention file', 'Update Do Not Send. Track Members and Medical Cost Ratio S:\AHP_BI\Finance & Risk\Financial Statements AHP\System Reporting\Balance', 0);
SET @task_44 := LAST_INSERT_ID();

UPDATE Audit_Log
SET task_id = @task_44, table_id = @task_44
WHERE audit_log_id = @al_t44;

-- Task 51
-- Send out MCR & Monthly Growth to AHS (Due 11/12 → Populate Financials)
INSERT INTO Audit_Log (task_id, user_id, prev_state, new_state, table_type, table_id)
VALUES (NULL, @user_alex, NULL, 'created task', 'Task', NULL);
SET @al_t45 := LAST_INSERT_ID();

INSERT INTO Timestamps (audit_log_id)
VALUES (@al_t45);
SET @ts_t45 := LAST_INSERT_ID();

INSERT INTO Task (due_date, ts_id, user_id, step_id, status_id, title, notes, is_deleted)
VALUES ('2025-11-12', @ts_t45, @user_alex, @step_populate, @status_ip,
        'Send out MCR & Monthly Growth to AHS', 'Email to be sent out after Board Reports are Final (when email is sent to AHS with location of Board Packs). No October numbers (forecast only)', 0);
SET @task_45 := LAST_INSERT_ID();

UPDATE Audit_Log
SET task_id = @task_45, table_id = @task_45
WHERE audit_log_id = @al_t45;


-- Task 52
-- Prepare Stop Loss Review and Submission to Redwood - over 100k (Due 12/08 → EXCLUDED: after cutoff)
-- Skipped


-- Task 53
-- Send OPEX update and deficit reserve update (Due 11/15 → Populate Financials)
INSERT INTO Audit_Log (task_id, user_id, prev_state, new_state, table_type, table_id)
VALUES (NULL, @user_aidan, NULL, 'created task', 'Task', NULL);
SET @al_t46 := LAST_INSERT_ID();

INSERT INTO Timestamps (audit_log_id)
VALUES (@al_t46);
SET @ts_t46 := LAST_INSERT_ID();

INSERT INTO Task (due_date, ts_id, user_id, step_id, status_id, title, notes, is_deleted)
VALUES ('2025-11-15', @ts_t46, @user_aidan, @step_populate, @status_ns,
        'Send OPEX update and deficit reserve update', NULL, 0);
SET @task_46 := LAST_INSERT_ID();

UPDATE Audit_Log
SET task_id = @task_46, table_id = @task_46
WHERE audit_log_id = @al_t46;


-- Task 54
-- Prepare preliminary forecasts - Nadia prep comments (Due 12/03 → Final JE Upload)
INSERT INTO Audit_Log (task_id, user_id, prev_state, new_state, table_type, table_id)
VALUES (NULL, @user_bakir, NULL, 'created task', 'Task', NULL);
SET @al_t47 := LAST_INSERT_ID();

INSERT INTO Timestamps (audit_log_id)
VALUES (@al_t47);
SET @ts_t47 := LAST_INSERT_ID();

INSERT INTO Task (due_date, ts_id, user_id, step_id, status_id, title, notes, is_deleted)
VALUES ('2025-12-03', @ts_t47, @user_bakir, @step_final, @status_ns,
        'Prepare preliminary forecasts - Nadia prep comments', NULL, 0);
SET @task_47 := LAST_INSERT_ID();

UPDATE Audit_Log
SET task_id = @task_47, table_id = @task_47
WHERE audit_log_id = @al_t47;


-- Task 55
-- Prepare preliminary forecasts - Jordan - Review (Due 12/03 → Final JE Upload)
INSERT INTO Audit_Log (task_id, user_id, prev_state, new_state, table_type, table_id)
VALUES (NULL, @user_alex, NULL, 'created task', 'Task', NULL);
SET @al_t48 := LAST_INSERT_ID();

INSERT INTO Timestamps (audit_log_id)
VALUES (@al_t48);
SET @ts_t48 := LAST_INSERT_ID();

INSERT INTO Task (due_date, ts_id, user_id, step_id, status_id, title, notes, is_deleted)
VALUES ('2025-12-03', @ts_t48, @user_alex, @step_final, @status_ip,
        'Prepare preliminary forecasts - Jordan - Review', NULL, 0);
SET @task_48 := LAST_INSERT_ID();

UPDATE Audit_Log
SET task_id = @task_48, table_id = @task_48
WHERE audit_log_id = @al_t48;


-- Task 56
-- Prepare preliminary forecasts - Paula prep final file and send out email (Due 12/03 → Final JE Upload)
INSERT INTO Audit_Log (task_id, user_id, prev_state, new_state, table_type, table_id)
VALUES (NULL, @user_aidan, NULL, 'created task', 'Task', NULL);
SET @al_t49 := LAST_INSERT_ID();

INSERT INTO Timestamps (audit_log_id)
VALUES (@al_t49);
SET @ts_t49 := LAST_INSERT_ID();

INSERT INTO Task (due_date, ts_id, user_id, step_id, status_id, title, notes, is_deleted)
VALUES ('2025-12-03', @ts_t49, @user_aidan, @step_final, @status_dn,
        'Prepare preliminary forecasts - Paula prep final file and send out email', NULL, 0);
SET @task_49 := LAST_INSERT_ID();

UPDATE Audit_Log
SET task_id = @task_49, table_id = @task_49
WHERE audit_log_id = @al_t49;


-- Task 57
-- Request updated % from Renee (Due 12/01 → Flash JE Upload)
INSERT INTO Audit_Log (task_id, user_id, prev_state, new_state, table_type, table_id)
VALUES (NULL, @user_bakir, NULL, 'created task', 'Task', NULL);
SET @al_t50 := LAST_INSERT_ID();

INSERT INTO Timestamps (audit_log_id)
VALUES (@al_t50);
SET @ts_t50 := LAST_INSERT_ID();

INSERT INTO Task (due_date, ts_id, user_id, step_id, status_id, title, notes, is_deleted)
VALUES ('2025-12-01', @ts_t50, @user_bakir, @step_flash, @status_ns,
        'Request updated % from Renee', NULL, 0);
SET @task_50 := LAST_INSERT_ID();

UPDATE Audit_Log
SET task_id = @task_50, table_id = @task_50
WHERE audit_log_id = @al_t50;


-- Task 58
-- Prepare Journal entry backup (do not email) (Due 11/10 → Populate Financials)
INSERT INTO Audit_Log (task_id, user_id, prev_state, new_state, table_type, table_id)
VALUES (NULL, @user_alex, NULL, 'created task', 'Task', NULL);
SET @al_t51 := LAST_INSERT_ID();

INSERT INTO Timestamps (audit_log_id)
VALUES (@al_t51);
SET @ts_t51 := LAST_INSERT_ID();

INSERT INTO Task (due_date, ts_id, user_id, step_id, status_id, title, notes, is_deleted)
VALUES ('2025-11-10', @ts_t51, @user_alex, @step_populate, @status_ip,
        'Prepare Journal entry backup (do not email)', 'S:\AHP_B\Finance & Risk\Financial Statements AHP\External Audit\FY25\Internal Controls\C-4, C-6, C-8 - Journal Entries', 0);
SET @task_51 := LAST_INSERT_ID();

UPDATE Audit_Log
SET task_id = @task_51, table_id = @task_51
WHERE audit_log_id = @al_t51;


-- Task 59
-- Prepare 5 Year plan (Due 03/31/2026 → EXCLUDED)
-- Skipped


-- Task 60
-- Prepare Reconciliation 113145 (Due 11/11 → Populate Financials)
INSERT INTO Audit_Log (task_id, user_id, prev_state, new_state, table_type, table_id)
VALUES (NULL, @user_aidan, NULL, 'created task', 'Task', NULL);
SET @al_t52 := LAST_INSERT_ID();

INSERT INTO Timestamps (audit_log_id)
VALUES (@al_t52);
SET @ts_t52 := LAST_INSERT_ID();

INSERT INTO Task (due_date, ts_id, user_id, step_id, status_id, title, notes, is_deleted)
VALUES ('2025-11-11', @ts_t52, @user_aidan, @step_populate, @status_ns,
        'Prepare Reconciliation 113145', '113145 - S:\FINANCE\1_WORKING\2025\1_ASSETS\3_... AND LEADSHEET', 0);
SET @task_52 := LAST_INSERT_ID();

UPDATE Audit_Log
SET task_id = @task_52, table_id = @task_52
WHERE audit_log_id = @al_t52;

-- Task 61
-- Prepare Reconciliation 211107 (Due 11/11 → Populate Financials)
INSERT INTO Audit_Log (task_id, user_id, prev_state, new_state, table_type, table_id)
VALUES (NULL, @user_bakir, NULL, 'created task', 'Task', NULL);
SET @al_t53 := LAST_INSERT_ID();

INSERT INTO Timestamps (audit_log_id)
VALUES (@al_t53);
SET @ts_t53 := LAST_INSERT_ID();

INSERT INTO Task (due_date, ts_id, user_id, step_id, status_id, title, notes, is_deleted)
VALUES ('2025-11-11', @ts_t53, @user_bakir, @step_populate, @status_ns,
        'Prepare Reconciliation 211107', '211107 -', 0);
SET @task_53 := LAST_INSERT_ID();

UPDATE Audit_Log
SET task_id = @task_53, table_id = @task_53
WHERE audit_log_id = @al_t53;


-- Task 62
-- Journal entry upload for AHS - Prep JE Upload (Due 12/05 → EXCLUDED: after cutoff)
-- Skipped


-- Task 63
-- Journal entry upload for AHS - Send to Nadia for review (Due 12/05 → EXCLUDED)
-- Skipped


-- Task 64
-- Journal entry upload for AHS - Send to Olivia and Priya (Due 12/05 → EXCLUDED)
-- Skipped


-- Task 65
-- Tie out financial statements after JE is posted (Due 11/12 → Populate Financials)
INSERT INTO Audit_Log (task_id, user_id, prev_state, new_state, table_type, table_id)
VALUES (NULL, @user_alex, NULL, 'created task', 'Task', NULL);
SET @al_t54 := LAST_INSERT_ID();

INSERT INTO Timestamps (audit_log_id)
VALUES (@al_t54);
SET @ts_t54 := LAST_INSERT_ID();

INSERT INTO Task (due_date, ts_id, user_id, step_id, status_id, title, notes, is_deleted)
VALUES ('2025-11-12', @ts_t54, @user_alex, @step_populate, @status_ip,
        'Tie out financial statements after JE is posted', 'After JE is posted, make sure all checks are $0 (everything is posted correctly and in the financials)', 0);
SET @task_54 := LAST_INSERT_ID();

UPDATE Audit_Log
SET task_id = @task_54, table_id = @task_54
WHERE audit_log_id = @al_t54;


-- Task 66
-- Update opex (Due 12/06 → EXCLUDED: after cutoff)
-- Skipped


-- Task 67
-- Roll forward financial prepared - Day after board reports are issued (Due 11/12 → Populate Financials)
INSERT INTO Audit_Log (task_id, user_id, prev_state, new_state, table_type, table_id)
VALUES (NULL, @user_aidan, NULL, 'created task', 'Task', NULL);
SET @al_t55 := LAST_INSERT_ID();

INSERT INTO Timestamps (audit_log_id)
VALUES (@al_t55);
SET @ts_t55 := LAST_INSERT_ID();

INSERT INTO Task (due_date, ts_id, user_id, step_id, status_id, title, notes, is_deleted)
VALUES ('2025-11-12', @ts_t55, @user_aidan, @step_populate, @status_ns,
        'Roll forward financial prepared - Day after board reports are issued', NULL, 0);
SET @task_55 := LAST_INSERT_ID();

UPDATE Audit_Log
SET task_id = @task_55, table_id = @task_55
WHERE audit_log_id = @al_t55;


-- Task 68
-- 1st review of plans and update estimates, forecast, payments (Due 11/20 → First Review Complete)
INSERT INTO Audit_Log (task_id, user_id, prev_state, new_state, table_type, table_id)
VALUES (NULL, @user_bakir, NULL, 'created task', 'Task', NULL);
SET @al_t56 := LAST_INSERT_ID();

INSERT INTO Timestamps (audit_log_id)
VALUES (@al_t56);
SET @ts_t56 := LAST_INSERT_ID();

INSERT INTO Task (due_date, ts_id, user_id, step_id, status_id, title, notes, is_deleted)
VALUES ('2025-11-20', @ts_t56, @user_bakir, @step_first, @status_ip,
        '1st review of plans and update estimates, forecast, payments', NULL, 0);
SET @task_56 := LAST_INSERT_ID();

UPDATE Audit_Log
SET task_id = @task_56, table_id = @task_56
WHERE audit_log_id = @al_t56;


-- Task 69
-- 2nd review of plans and estimates & forecast - Elimination review Deduction % updated (Due 12/02 → Flash JE Upload)
INSERT INTO Audit_Log (task_id, user_id, prev_state, new_state, table_type, table_id)
VALUES (NULL, @user_alex, NULL, 'created task', 'Task', NULL);
SET @al_t57 := LAST_INSERT_ID();

INSERT INTO Timestamps (audit_log_id)
VALUES (@al_t57);
SET @ts_t57 := LAST_INSERT_ID();

INSERT INTO Task (due_date, ts_id, user_id, step_id, status_id, title, notes, is_deleted)
VALUES ('2025-12-02', @ts_t57, @user_alex, @step_flash, @status_ns,
        '2nd review of plans and estimates & forecast - Elimination review Deduction % updated', NULL, 0);
SET @task_57 := LAST_INSERT_ID();

UPDATE Audit_Log
SET task_id = @task_57, table_id = @task_57
WHERE audit_log_id = @al_t57;


-- Task 70
-- 2nd review of plans and estimates & forecast - Health Plan Reviewed (Due 12/02 → Flash JE Upload)
INSERT INTO Audit_Log (task_id, user_id, prev_state, new_state, table_type, table_id)
VALUES (NULL, @user_aidan, NULL, 'created task', 'Task', NULL);
SET @al_t58 := LAST_INSERT_ID();

INSERT INTO Timestamps (audit_log_id)
VALUES (@al_t58);
SET @ts_t58 := LAST_INSERT_ID();

INSERT INTO Task (due_date, ts_id, user_id, step_id, status_id, title, notes, is_deleted)
VALUES ('2025-12-02', @ts_t58, @user_aidan, @step_flash, @status_ip,
        '2nd review of plans and estimates & forecast - Health Plan Reviewed', NULL, 0);
SET @task_58 := LAST_INSERT_ID();

UPDATE Audit_Log
SET task_id = @task_58, table_id = @task_58
WHERE audit_log_id = @al_t58;

-- Task 71
-- Update Triangles - Bluewater Advantage (Due 11/12 → Populate Financials)
INSERT INTO Audit_Log (task_id, user_id, prev_state, new_state, table_type, table_id)
VALUES (NULL, @user_bakir, NULL, 'created task', 'Task', NULL);
SET @al_t59 := LAST_INSERT_ID();

INSERT INTO Timestamps (audit_log_id)
VALUES (@al_t59);
SET @ts_t59 := LAST_INSERT_ID();

INSERT INTO Task (due_date, ts_id, user_id, step_id, status_id, title, notes, is_deleted)
VALUES ('2025-11-12', @ts_t59, @user_bakir, @step_populate, @status_ns,
        'Update Triangles - Bluewater Advantage', NULL, 0);
SET @task_59 := LAST_INSERT_ID();

UPDATE Audit_Log
SET task_id = @task_59, table_id = @task_59
WHERE audit_log_id = @al_t59;


-- Task 72
-- Update Triangles - Bluewater CarePlus (Due 11/12 → Populate Financials)
INSERT INTO Audit_Log (task_id, user_id, prev_state, new_state, table_type, table_id)
VALUES (NULL, @user_alex, NULL, 'created task', 'Task', NULL);
SET @al_t60 := LAST_INSERT_ID();

INSERT INTO Timestamps (audit_log_id)
VALUES (@al_t60);
SET @ts_t60 := LAST_INSERT_ID();

INSERT INTO Task (due_date, ts_id, user_id, step_id, status_id, title, notes, is_deleted)
VALUES ('2025-11-12', @ts_t60, @user_alex, @step_populate, @status_ns,
        'Update Triangles - Bluewater CarePlus', NULL, 0);
SET @task_60 := LAST_INSERT_ID();

UPDATE Audit_Log
SET task_id = @task_60, table_id = @task_60
WHERE audit_log_id = @al_t60;


-- Task 73
-- Update Triangles - WH Data Only (Due 11/12 → Populate Financials)
INSERT INTO Audit_Log (task_id, user_id, prev_state, new_state, table_type, table_id)
VALUES (NULL, @user_aidan, NULL, 'created task', 'Task', NULL);
SET @al_t61 := LAST_INSERT_ID();

INSERT INTO Timestamps (audit_log_id)
VALUES (@al_t61);
SET @ts_t61 := LAST_INSERT_ID();

INSERT INTO Task (due_date, ts_id, user_id, step_id, status_id, title, notes, is_deleted)
VALUES ('2025-11-12', @ts_t61, @user_aidan, @step_populate, @status_ns,
        'Update Triangles - WH Data Only', NULL, 0);
SET @task_61 := LAST_INSERT_ID();

UPDATE Audit_Log
SET task_id = @task_61, table_id = @task_61
WHERE audit_log_id = @al_t61;


-- Task 74
-- Update Triangles - Unity Focus (Due 11/12 → Populate Financials)
INSERT INTO Audit_Log (task_id, user_id, prev_state, new_state, table_type, table_id)
VALUES (NULL, @user_bakir, NULL, 'created task', 'Task', NULL);
SET @al_t62 := LAST_INSERT_ID();

INSERT INTO Timestamps (audit_log_id)
VALUES (@al_t62);
SET @ts_t62 := LAST_INSERT_ID();

INSERT INTO Task (due_date, ts_id, user_id, step_id, status_id, title, notes, is_deleted)
VALUES ('2025-11-12', @ts_t62, @user_bakir, @step_populate, @status_ns,
        'Update Triangles - Unity Focus', NULL, 0);
SET @task_62 := LAST_INSERT_ID();

UPDATE Audit_Log
SET task_id = @task_62, table_id = @task_62
WHERE audit_log_id = @al_t62;


-- Task 75
-- Update Triangles - AHS Employee Plan 2024 (Due 11/12 → Populate Financials)
INSERT INTO Audit_Log (task_id, user_id, prev_state, new_state, table_type, table_id)
VALUES (NULL, @user_alex, NULL, 'created task', 'Task', NULL);
SET @al_t63 := LAST_INSERT_ID();

INSERT INTO Timestamps (audit_log_id)
VALUES (@al_t63);
SET @ts_t63 := LAST_INSERT_ID();

INSERT INTO Task (due_date, ts_id, user_id, step_id, status_id, title, notes, is_deleted)
VALUES ('2025-11-12', @ts_t63, @user_alex, @step_populate, @status_ns,
        'Update Triangles - AHS Employee Plan 2024', NULL, 0);
SET @task_63 := LAST_INSERT_ID();

UPDATE Audit_Log
SET task_id = @task_63, table_id = @task_63
WHERE audit_log_id = @al_t63;


-- Task 76
-- Update Triangles - Unity Senior (upside only) (Due 11/12 → Populate Financials)
INSERT INTO Audit_Log (task_id, user_id, prev_state, new_state, table_type, table_id)
VALUES (NULL, @user_aidan, NULL, 'created task', 'Task', NULL);
SET @al_t64 := LAST_INSERT_ID();

INSERT INTO Timestamps (audit_log_id)
VALUES (@al_t64);
SET @ts_t64 := LAST_INSERT_ID();

INSERT INTO Task (due_date, ts_id, user_id, step_id, status_id, title, notes, is_deleted)
VALUES ('2025-11-12', @ts_t64, @user_aidan, @step_populate, @status_ns,
        'Update Triangles - Unity Senior (upside only)', NULL, 0);
SET @task_64 := LAST_INSERT_ID();

UPDATE Audit_Log
SET task_id = @task_64, table_id = @task_64
WHERE audit_log_id = @al_t64;


-- Task 77
-- Update Triangles - ACO Connect (Due 11/12 → Populate Financials)
INSERT INTO Audit_Log (task_id, user_id, prev_state, new_state, table_type, table_id)
VALUES (NULL, @user_bakir, NULL, 'created task', 'Task', NULL);
SET @al_t65 := LAST_INSERT_ID();

INSERT INTO Timestamps (audit_log_id)
VALUES (@al_t65);
SET @ts_t65 := LAST_INSERT_ID();

INSERT INTO Task (due_date, ts_id, user_id, step_id, status_id, title, notes, is_deleted)
VALUES ('2025-11-12', @ts_t65, @user_bakir, @step_populate, @status_ns,
        'Update Triangles - ACO Connect', NULL, 0);
SET @task_65 := LAST_INSERT_ID();

UPDATE Audit_Log
SET task_id = @task_65, table_id = @task_65
WHERE audit_log_id = @al_t65;


-- Task 78
-- Update Triangles - Cascadia MA (Summary files) (Due 11/12 → Populate Financials)
-- (This appears again in TXT — we preserve the order exactly)
INSERT INTO Audit_Log (task_id, user_id, prev_state, new_state, table_type, table_id)
VALUES (NULL, @user_alex, NULL, 'created task', 'Task', NULL);
SET @al_t66 := LAST_INSERT_ID();

INSERT INTO Timestamps (audit_log_id)
VALUES (@al_t66);
SET @ts_t66 := LAST_INSERT_ID();

INSERT INTO Task (due_date, ts_id, user_id, step_id, status_id, title, notes, is_deleted)
VALUES ('2025-11-12', @ts_t66, @user_alex, @step_populate, @status_ns,
        'Update Triangles - Cascadia MA (Summary files)', NULL, 0);
SET @task_66 := LAST_INSERT_ID();

UPDATE Audit_Log
SET task_id = @task_66, table_id = @task_66
WHERE audit_log_id = @al_t66;


-- Task 79
-- Update Triangles - Cascadia Large (Summary files) (Due 11/12 → Populate Financials)
INSERT INTO Audit_Log (task_id, user_id, prev_state, new_state, table_type, table_id)
VALUES (NULL, @user_aidan, NULL, 'created task', 'Task', NULL);
SET @al_t67 := LAST_INSERT_ID();

INSERT INTO Timestamps (audit_log_id)
VALUES (@al_t67);
SET @ts_t67 := LAST_INSERT_ID();

INSERT INTO Task (due_date, ts_id, user_id, step_id, status_id, title, notes, is_deleted)
VALUES ('2025-11-12', @ts_t67, @user_aidan, @step_populate, @status_ns,
        'Update Triangles - Cascadia Large (Summary files)', NULL, 0);
SET @task_67 := LAST_INSERT_ID();

UPDATE Audit_Log
SET task_id = @task_67, table_id = @task_67
WHERE audit_log_id = @al_t67;


-- Task 80
-- Update Triangles - Cascadia Small (Summary files) (Due 11/12 → Populate Financials)
INSERT INTO Audit_Log (task_id, user_id, prev_state, new_state, table_type, table_id)
VALUES (NULL, @user_bakir, NULL, 'created task', 'Task', NULL);
SET @al_t68 := LAST_INSERT_ID();

INSERT INTO Timestamps (audit_log_id)
VALUES (@al_t68);
SET @ts_t68 := LAST_INSERT_ID();

INSERT INTO Task (due_date, ts_id, user_id, step_id, status_id, title, notes, is_deleted)
VALUES ('2025-11-12', @ts_t68, @user_bakir, @step_populate, @status_ns,
        'Update Triangles - Cascadia Small (Summary files)', NULL, 0);
SET @task_68 := LAST_INSERT_ID();

UPDATE Audit_Log
SET task_id = @task_68, table_id = @task_68
WHERE audit_log_id = @al_t68;



-- Task 86
-- Update AHP Portfolio Overview (Due 12/06 → EXCLUDED: after cutoff)
-- Skipped




-- Task 89
-- Prepare Stop Loss Review and Submission to Redwood - over 100k (Due 12/08 → EXCLUDED)
-- Skipped























/* =========================
   7) Example comments
   ========================= */
-- Comment on FR #1 (task_5)
INSERT INTO `Audit_Log` (`task_id`, `user_id`, `prev_state`, `new_state`, `table_type`, `table_id`)
VALUES (@task_5, @user_alex, NULL, 'added comment', 'Comments', NULL);
SET @al_c1 := LAST_INSERT_ID();
INSERT INTO `Timestamps` (`audit_log_id`) VALUES (@al_c1);
SET @ts_c1 := LAST_INSERT_ID();
INSERT INTO `Comments` (`user_id`, `task_id`, `ts_id`, `comment`)
VALUES (@user_alex, @task_5, @ts_c1, 'Variance spikes driven by prepaid timing.');

-- Comment on PF #3 (task_3)
INSERT INTO `Audit_Log` (`task_id`, `user_id`, `prev_state`, `new_state`, `table_type`, `table_id`)
VALUES (@task_3, @user_bakir, NULL, 'added comment', 'Comments', NULL);
SET @al_c2 := LAST_INSERT_ID();
INSERT INTO `Timestamps` (`audit_log_id`) VALUES (@al_c2);
SET @ts_c2 := LAST_INSERT_ID();
INSERT INTO `Comments` (`user_id`, `task_id`, `ts_id`, `comment`)
VALUES (@user_bakir, @task_3, @ts_c2, 'Need final accruals from FP&A.');

-- Comment on FI #4 (task_20)
INSERT INTO `Audit_Log` (`task_id`, `user_id`, `prev_state`, `new_state`, `table_type`, `table_id`)
VALUES (@task_20, @user_aidan, NULL, 'added comment', 'Comments', NULL);
SET @al_c3 := LAST_INSERT_ID();
INSERT INTO `Timestamps` (`audit_log_id`) VALUES (@al_c3);
SET @ts_c3 := LAST_INSERT_ID();
INSERT INTO `Comments` (`user_id`, `task_id`, `ts_id`, `comment`)
VALUES (@user_aidan, @task_20, @ts_c3, 'Provision draft expected EOD.');

-- done
SET FOREIGN_KEY_CHECKS = @OLD_FK;
