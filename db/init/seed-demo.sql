-- db/seed.sql — demo-rich seed (20 tasks total, with notes)
-- Matches your 5 dashboard steps; each task includes a 'notes' value.

SET @OLD_FK = @@FOREIGN_KEY_CHECKS; SET FOREIGN_KEY_CHECKS = 0;
USE `dashboard`;

-- Optional: clean dev data so this seed is deterministic
TRUNCATE TABLE `Comments`;
TRUNCATE TABLE `User_Task_Read_Markers`;
TRUNCATE TABLE `Task`;
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
INSERT INTO `Users` (`username`, `email`, `password`, `is_admin`, `first_name`, `last_name`, `ts_id`, `color_code`, `is_deleted`, `is_invited`) VALUES
  -- Passwords below are hashed with bcrypt. Plaintext (for demo):
  --   atracy -> some_password_for_aidan
  --   bgrbic -> some_password_for_bakir
  --   adaniluc -> some_password_for_alex
  ('atracy',  'aidan.tracy@u.boisestate.edu', '$2b$12$JSrJKA7xFs/0lqoMbFyCF.3txyoY3azN.fb0IZ4VywkgLfFRuK3Kq', 1, 'Aidan', 'Tracy',  NULL, '#2563EB', 0, 0),
  ('bgrbic',  'bakir.grbic@u.boisestate.edu', '$2b$12$7hOWLOeLVrrAUmYblRXel.Qbh6CdyRMirVNkd12/rUD8CGVzHJYbK', 1, 'Bakir', 'Grbic',  NULL, '#10B981', 0, 0),
  ('adaniluc','Alex.daniluc@u.boisestate.edu','$2b$12$DdD85RrhqdxwmHsg.aabLuGwKcJ6CCX0YBQ/LeTybmZG2nxsgJn5S', 0, 'Alex',  'Daniluc', NULL, '#A855F7', 0, 0);

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
   6) Sample tasks — 4 per step
   Populate Financials
   ========================= */
-- PF #1
INSERT INTO `Audit_Log` (`task_id`, `user_id`, `prev_state`, `new_state`, `table_type`, `table_id`)
VALUES (NULL, @user_aidan, NULL, 'created task', 'Task', NULL);
SET @al_t1 := LAST_INSERT_ID();
INSERT INTO `Timestamps` (`audit_log_id`) VALUES (@al_t1);
SET @ts_t1 := LAST_INSERT_ID();
INSERT INTO `Task` (`due_date`, `ts_id`, `user_id`, `step_id`, `status_id`, `title`, `notes`)
VALUES (DATE_ADD(CURDATE(), INTERVAL 2 DAY), @ts_t1, @user_aidan, @step_populate, @status_ns, 'Load bank feeds & trial balance', 'Bank feeds loading; TB ties. Waiting on one account mapping.');
SET @task_1 := LAST_INSERT_ID();
UPDATE `Audit_Log` SET `task_id`=@task_1, `table_id`=@task_1 WHERE `audit_log_id`=@al_t1;

-- PF #2 (overdue)
INSERT INTO `Audit_Log` (`task_id`, `user_id`, `prev_state`, `new_state`, `table_type`, `table_id`)
VALUES (NULL, @user_bakir, NULL, 'created task', 'Task', NULL);
SET @al_t2 := LAST_INSERT_ID();
INSERT INTO `Timestamps` (`audit_log_id`) VALUES (@al_t2);
SET @ts_t2 := LAST_INSERT_ID();
INSERT INTO `Task` (`due_date`, `ts_id`, `user_id`, `step_id`, `status_id`, `title`, `notes`)
VALUES (DATE_SUB(CURDATE(), INTERVAL 1 DAY), @ts_t2, @user_bakir, @step_populate, @status_ip, 'Import AP/AR subledger balances', 'AP subledger imported. AR pending credit memo batch.');
SET @task_2 := LAST_INSERT_ID();
UPDATE `Audit_Log` SET `task_id`=@task_2, `table_id`=@task_2 WHERE `audit_log_id`=@al_t2;

-- PF #3
INSERT INTO `Audit_Log` (`task_id`, `user_id`, `prev_state`, `new_state`, `table_type`, `table_id`)
VALUES (NULL, @user_alex, NULL, 'created task', 'Task', NULL);
SET @al_t3 := LAST_INSERT_ID();
INSERT INTO `Timestamps` (`audit_log_id`) VALUES (@al_t3);
SET @ts_t3 := LAST_INSERT_ID();
INSERT INTO `Task` (`due_date`, `ts_id`, `user_id`, `step_id`, `status_id`, `title`, `notes`)
VALUES (DATE_ADD(CURDATE(), INTERVAL 1 DAY), @ts_t3, @user_alex, @step_populate, @status_sk, 'Post monthly accrual templates', 'Waiting for final accrual schedule from FP&A.');
SET @task_3 := LAST_INSERT_ID();
UPDATE `Audit_Log` SET `task_id`=@task_3, `table_id`=@task_3 WHERE `audit_log_id`=@al_t3;

-- PF #4
INSERT INTO `Audit_Log` (`task_id`, `user_id`, `prev_state`, `new_state`, `table_type`, `table_id`)
VALUES (NULL, @user_aidan, NULL, 'created task', 'Task', NULL);
SET @al_t4 := LAST_INSERT_ID();
INSERT INTO `Timestamps` (`audit_log_id`) VALUES (@al_t4);
SET @ts_t4 := LAST_INSERT_ID();
INSERT INTO `Task` (`due_date`, `ts_id`, `user_id`, `step_id`, `status_id`, `title`, `notes`)
VALUES (DATE_ADD(CURDATE(), INTERVAL 3 DAY), @ts_t4, @user_aidan, @step_populate, @status_dn, 'Refresh FX rates & mapping rules', 'FX map refreshed; rates loaded for current month.');
SET @task_4 := LAST_INSERT_ID();
UPDATE `Audit_Log` SET `task_id`=@task_4, `table_id`=@task_4 WHERE `audit_log_id`=@al_t4;












/* =========================
   First Review Complete
   ========================= */
-- FR #1
INSERT INTO `Audit_Log` (`task_id`, `user_id`, `prev_state`, `new_state`, `table_type`, `table_id`)
VALUES (NULL, @user_bakir, NULL, 'created task', 'Task', NULL);
SET @al_t5 := LAST_INSERT_ID();
INSERT INTO `Timestamps` (`audit_log_id`) VALUES (@al_t5);
SET @ts_t5 := LAST_INSERT_ID();
INSERT INTO `Task` (`due_date`, `ts_id`, `user_id`, `step_id`, `status_id`, `title`, `notes`)
VALUES (DATE_ADD(CURDATE(), INTERVAL 4 DAY), @ts_t5, @user_bakir, @step_first, @status_ip, 'Variance check vs. prior month', 'Top variances flagged; detail review in progress.');
SET @task_5 := LAST_INSERT_ID();
UPDATE `Audit_Log` SET `task_id`=@task_5, `table_id`=@task_5 WHERE `audit_log_id`=@al_t5;

-- FR #2
INSERT INTO `Audit_Log` (`task_id`, `user_id`, `prev_state`, `new_state`, `table_type`, `table_id`)
VALUES (NULL, @user_alex, NULL, 'created task', 'Task', NULL);
SET @al_t6 := LAST_INSERT_ID();
INSERT INTO `Timestamps` (`audit_log_id`) VALUES (@al_t6);
SET @ts_t6 := LAST_INSERT_ID();
INSERT INTO `Task` (`due_date`, `ts_id`, `user_id`, `step_id`, `status_id`, `title`, `notes`)
VALUES (DATE_ADD(CURDATE(), INTERVAL 5 DAY), @ts_t6, @user_alex, @step_first, @status_ns, 'Review top 10 P&L movements', 'Focus on COGS and payroll variances.');
SET @task_6 := LAST_INSERT_ID();
UPDATE `Audit_Log` SET `task_id`=@task_6, `table_id`=@task_6 WHERE `audit_log_id`=@al_t6;

-- FR #3 (overdue)
INSERT INTO `Audit_Log` (`task_id`, `user_id`, `prev_state`, `new_state`, `table_type`, `table_id`)
VALUES (NULL, @user_aidan, NULL, 'created task', 'Task', NULL);
SET @al_t7 := LAST_INSERT_ID();
INSERT INTO `Timestamps` (`audit_log_id`) VALUES (@al_t7);
SET @ts_t7 := LAST_INSERT_ID();
INSERT INTO `Task` (`due_date`, `ts_id`, `user_id`, `step_id`, `status_id`, `title`, `notes`)
VALUES (DATE_SUB(CURDATE(), INTERVAL 2 DAY), @ts_t7, @user_aidan, @step_first, @status_sk, 'Clear data quality exceptions', 'Data exception report attached; pending owner response.');
SET @task_7 := LAST_INSERT_ID();
UPDATE `Audit_Log` SET `task_id`=@task_7, `table_id`=@task_7 WHERE `audit_log_id`=@al_t7;

-- FR #4
INSERT INTO `Audit_Log` (`task_id`, `user_id`, `prev_state`, `new_state`, `table_type`, `table_id`)
VALUES (NULL, @user_bakir, NULL, 'created task', 'Task', NULL);
SET @al_t8 := LAST_INSERT_ID();
INSERT INTO `Timestamps` (`audit_log_id`) VALUES (@al_t8);
SET @ts_t8 := LAST_INSERT_ID();
INSERT INTO `Task` (`due_date`, `ts_id`, `user_id`, `step_id`, `status_id`, `title`, `notes`)
VALUES (DATE_ADD(CURDATE(), INTERVAL 3 DAY), @ts_t8, @user_bakir, @step_first, @status_dn, 'Tie-out balance sheet rollforwards', 'Rollforward ties; attaching support to folder.');
SET @task_8 := LAST_INSERT_ID();
UPDATE `Audit_Log` SET `task_id`=@task_8, `table_id`=@task_8 WHERE `audit_log_id`=@al_t8;















/* =========================
   Second Review Complete
   ========================= */
-- SR #1
INSERT INTO `Audit_Log` (`task_id`, `user_id`, `prev_state`, `new_state`, `table_type`, `table_id`)
VALUES (NULL, @user_alex, NULL, 'created task', 'Task', NULL);
SET @al_t9 := LAST_INSERT_ID();
INSERT INTO `Timestamps` (`audit_log_id`) VALUES (@al_t9);
SET @ts_t9 := LAST_INSERT_ID();
INSERT INTO `Task` (`due_date`, `ts_id`, `user_id`, `step_id`, `status_id`, `title`, `notes`)
VALUES (DATE_ADD(CURDATE(), INTERVAL 6 DAY), @ts_t9, @user_alex, @step_second, @status_ns, 'Reconcile open items list', 'Most items cleared; two pending owner confirmations.');
SET @task_9 := LAST_INSERT_ID();
UPDATE `Audit_Log` SET `task_id`=@task_9, `table_id`=@task_9 WHERE `audit_log_id`=@al_t9;

-- SR #2
INSERT INTO `Audit_Log` (`task_id`, `user_id`, `prev_state`, `new_state`, `table_type`, `table_id`)
VALUES (NULL, @user_aidan, NULL, 'created task', 'Task', NULL);
SET @al_t10 := LAST_INSERT_ID();
INSERT INTO `Timestamps` (`audit_log_id`) VALUES (@al_t10);
SET @ts_t10 := LAST_INSERT_ID();
INSERT INTO `Task` (`due_date`, `ts_id`, `user_id`, `step_id`, `status_id`, `title`, `notes`)
VALUES (DATE_ADD(CURDATE(), INTERVAL 7 DAY), @ts_t10, @user_aidan, @step_second, @status_ip, 'Review flux commentary (material changes)', 'Draft commentary prepared; awaiting manager signoff.');
SET @task_10 := LAST_INSERT_ID();
UPDATE `Audit_Log` SET `task_id`=@task_10, `table_id`=@task_10 WHERE `audit_log_id`=@al_t10;

-- SR #3
INSERT INTO `Audit_Log` (`task_id`, `user_id`, `prev_state`, `new_state`, `table_type`, `table_id`)
VALUES (NULL, @user_bakir, NULL, 'created task', 'Task', NULL);
SET @al_t11 := LAST_INSERT_ID();
INSERT INTO `Timestamps` (`audit_log_id`) VALUES (@al_t11);
SET @ts_t11 := LAST_INSERT_ID();
INSERT INTO `Task` (`due_date`, `ts_id`, `user_id`, `step_id`, `status_id`, `title`, `notes`)
VALUES (DATE_ADD(CURDATE(), INTERVAL 8 DAY), @ts_t11, @user_bakir, @step_second, @status_sk, 'Check intercompany eliminations', 'Mismatch on entity 2203; pending IC team reply.');
SET @task_11 := LAST_INSERT_ID();
UPDATE `Audit_Log` SET `task_id`=@task_11, `table_id`=@task_11 WHERE `audit_log_id`=@al_t11;

-- SR #4 (done)
INSERT INTO `Audit_Log` (`task_id`, `user_id`, `prev_state`, `new_state`, `table_type`, `table_id`)
VALUES (NULL, @user_alex, NULL, 'created task', 'Task', NULL);
SET @al_t12 := LAST_INSERT_ID();
INSERT INTO `Timestamps` (`audit_log_id`) VALUES (@al_t12);
SET @ts_t12 := LAST_INSERT_ID();
INSERT INTO `Task` (`due_date`, `ts_id`, `user_id`, `step_id`, `status_id`, `title`, `notes`)
VALUES (DATE_ADD(CURDATE(), INTERVAL 5 DAY), @ts_t12, @user_alex, @step_second, @status_dn, 'Validate cash flow mapping', 'Mapping validated; handing off for posting.');
SET @task_12 := LAST_INSERT_ID();
UPDATE `Audit_Log` SET `task_id`=@task_12, `table_id`=@task_12 WHERE `audit_log_id`=@al_t12;








/* =========================
   Flash JE Upload
   ========================= */
-- FJ #1 (stuck)
INSERT INTO `Audit_Log` (`task_id`, `user_id`, `prev_state`, `new_state`, `table_type`, `table_id`)
VALUES (NULL, @user_aidan, NULL, 'created task', 'Task', NULL);
SET @al_t13 := LAST_INSERT_ID();
INSERT INTO `Timestamps` (`audit_log_id`) VALUES (@al_t13);
SET @ts_t13 := LAST_INSERT_ID();
INSERT INTO `Task` (`due_date`, `ts_id`, `user_id`, `step_id`, `status_id`, `title`, `notes`)
VALUES (DATE_ADD(CURDATE(), INTERVAL 8 DAY), @ts_t13, @user_aidan, @step_flash, @status_sk, 'Prepare flash entries package', 'Draft package ready; missing one support schedule.');
SET @task_13 := LAST_INSERT_ID();
UPDATE `Audit_Log` SET `task_id`=@task_13, `table_id`=@task_13 WHERE `audit_log_id`=@al_t13;

-- FJ #2
INSERT INTO `Audit_Log` (`task_id`, `user_id`, `prev_state`, `new_state`, `table_type`, `table_id`)
VALUES (NULL, @user_bakir, NULL, 'created task', 'Task', NULL);
SET @al_t14 := LAST_INSERT_ID();
INSERT INTO `Timestamps` (`audit_log_id`) VALUES (@al_t14);
SET @ts_t14 := LAST_INSERT_ID();
INSERT INTO `Task` (`due_date`, `ts_id`, `user_id`, `step_id`, `status_id`, `title`, `notes`)
VALUES (DATE_ADD(CURDATE(), INTERVAL 9 DAY), @ts_t14, @user_bakir, @step_flash, @status_ip, 'Draft JE for prepaid amortization', 'Template reviewed; waiting for prepaid schedule.');
SET @task_14 := LAST_INSERT_ID();
UPDATE `Audit_Log` SET `task_id`=@task_14, `table_id`=@task_14 WHERE `audit_log_id`=@al_t14;

-- FJ #3
INSERT INTO `Audit_Log` (`task_id`, `user_id`, `prev_state`, `new_state`, `table_type`, `table_id`)
VALUES (NULL, @user_alex, NULL, 'created task', 'Task', NULL);
SET @al_t15 := LAST_INSERT_ID();
INSERT INTO `Timestamps` (`audit_log_id`) VALUES (@al_t15);
SET @ts_t15 := LAST_INSERT_ID();
INSERT INTO `Task` (`due_date`, `ts_id`, `user_id`, `step_id`, `status_id`, `title`, `notes`)
VALUES (DATE_ADD(CURDATE(), INTERVAL 7 DAY), @ts_t15, @user_alex, @step_flash, @status_ns, 'Upload payroll accruals', 'Payroll accruals queued for review.');
SET @task_15 := LAST_INSERT_ID();
UPDATE `Audit_Log` SET `task_id`=@task_15, `table_id`=@task_15 WHERE `audit_log_id`=@al_t15;

-- FJ #4 (done)
INSERT INTO `Audit_Log` (`task_id`, `user_id`, `prev_state`, `new_state`, `table_type`, `table_id`)
VALUES (NULL, @user_aidan, NULL, 'created task', 'Task', NULL);
SET @al_t16 := LAST_INSERT_ID();
INSERT INTO `Timestamps` (`audit_log_id`) VALUES (@al_t16);
SET @ts_t16 := LAST_INSERT_ID();
INSERT INTO `Task` (`due_date`, `ts_id`, `user_id`, `step_id`, `status_id`, `title`, `notes`)
VALUES (DATE_ADD(CURDATE(), INTERVAL 6 DAY), @ts_t16, @user_aidan, @step_flash, @status_dn, 'Reverse prior month temporary entries', 'Temp entries reversed and verified.');
SET @task_16 := LAST_INSERT_ID();
UPDATE `Audit_Log` SET `task_id`=@task_16, `table_id`=@task_16 WHERE `audit_log_id`=@al_t16;


/* =========================
   Final JE Upload
   ========================= */
-- FI #1
INSERT INTO `Audit_Log` (`task_id`, `user_id`, `prev_state`, `new_state`, `table_type`, `table_id`)
VALUES (NULL, @user_bakir, NULL, 'created task', 'Task', NULL);
SET @al_t17 := LAST_INSERT_ID();
INSERT INTO `Timestamps` (`audit_log_id`) VALUES (@al_t17);
SET @ts_t17 := LAST_INSERT_ID();
INSERT INTO `Task` (`due_date`, `ts_id`, `user_id`, `step_id`, `status_id`, `title`, `notes`)
VALUES (DATE_ADD(CURDATE(), INTERVAL 10 DAY), @ts_t17, @user_bakir, @step_final, @status_ns, 'Post final adjusting entries', 'Final A/JE list compiled — ready for approval.');
SET @task_17 := LAST_INSERT_ID();
UPDATE `Audit_Log` SET `task_id`=@task_17, `table_id`=@task_17 WHERE `audit_log_id`=@al_t17;

-- FI #2 (done)
INSERT INTO `Audit_Log` (`task_id`, `user_id`, `prev_state`, `new_state`, `table_type`, `table_id`)
VALUES (NULL, @user_alex, NULL, 'created task', 'Task', NULL);
SET @al_t18 := LAST_INSERT_ID();
INSERT INTO `Timestamps` (`audit_log_id`) VALUES (@al_t18);
SET @ts_t18 := LAST_INSERT_ID();
INSERT INTO `Task` (`due_date`, `ts_id`, `user_id`, `step_id`, `status_id`, `title`, `notes`)
VALUES (DATE_ADD(CURDATE(), INTERVAL 11 DAY), @ts_t18, @user_alex, @step_final, @status_dn, 'Post depreciation run', 'Depreciation posted; tie-out complete.');
SET @task_18 := LAST_INSERT_ID();
UPDATE `Audit_Log` SET `task_id`=@task_18, `table_id`=@task_18 WHERE `audit_log_id`=@al_t18;

-- FI #3 (in progress)
INSERT INTO `Audit_Log` (`task_id`, `user_id`, `prev_state`, `new_state`, `table_type`, `table_id`)
VALUES (NULL, @user_aidan, NULL, 'created task', 'Task', NULL);
SET @al_t19 := LAST_INSERT_ID();
INSERT INTO `Timestamps` (`audit_log_id`) VALUES (@al_t19);
SET @ts_t19 := LAST_INSERT_ID();
INSERT INTO `Task` (`due_date`, `ts_id`, `user_id`, `step_id`, `status_id`, `title`, `notes`)
VALUES (DATE_ADD(CURDATE(), INTERVAL 12 DAY), @ts_t19, @user_aidan, @step_final, @status_ip, 'Close revenue deferrals', 'Deferrals matrix prepared; awaiting CFO review.');
SET @task_19 := LAST_INSERT_ID();
UPDATE `Audit_Log` SET `task_id`=@task_19, `table_id`=@task_19 WHERE `audit_log_id`=@al_t19;

-- FI #4 (stuck)
INSERT INTO `Audit_Log` (`task_id`, `user_id`, `prev_state`, `new_state`, `table_type`, `table_id`)
VALUES (NULL, @user_bakir, NULL, 'created task', 'Task', NULL);
SET @al_t20 := LAST_INSERT_ID();
INSERT INTO `Timestamps` (`audit_log_id`) VALUES (@al_t20);
SET @ts_t20 := LAST_INSERT_ID();
INSERT INTO `Task` (`due_date`, `ts_id`, `user_id`, `step_id`, `status_id`, `title`, `notes`)
VALUES (DATE_ADD(CURDATE(), INTERVAL 9 DAY), @ts_t20, @user_bakir, @step_final, @status_sk, 'Finalize tax provision & true-ups', 'Tax team sent draft; reconciling 2 items.');
SET @task_20 := LAST_INSERT_ID();
UPDATE `Audit_Log` SET `task_id`=@task_20, `table_id`=@task_20 WHERE `audit_log_id`=@al_t20;



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
