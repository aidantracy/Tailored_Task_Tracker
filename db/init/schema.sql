-- MySQL Workbench Forward Engineering

SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0;
SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0;
SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='ONLY_FULL_GROUP_BY,STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION';


CREATE SCHEMA IF NOT EXISTS `dashboard`
  DEFAULT CHARACTER SET utf8mb4
  COLLATE utf8mb4_0900_ai_ci;
USE `dashboard`;

-- =========================
-- Phase 1: Tables (no FKs)
-- =========================

CREATE TABLE IF NOT EXISTS `Dashboard` (
  `dashboard_id` INT NOT NULL AUTO_INCREMENT,
  `month_key` VARCHAR(7) NOT NULL UNIQUE, -- YYYY-MM  is the key
  `start_date` DATE NOT NULL,
  `end_date` DATE NOT NULL,
  PRIMARY KEY (`dashboard_id`)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS `Business_Day` (
  `business_day_id` INT NOT NULL AUTO_INCREMENT,
  `business_day` INT(31) NULL,
  PRIMARY KEY (`business_day_id`)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS `Step` (
  `step_id` INT NOT NULL AUTO_INCREMENT,
  `dashboard_id` INT NOT NULL,
  `business_day_id` INT NOT NULL,
  `step_title` VARCHAR(255) NULL,
  PRIMARY KEY (`step_id`),
  INDEX `idx_step_dashboard` (`dashboard_id`),
  INDEX `idx_step_business_day` (`business_day_id`)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS `Status` (
  `status_id` INT NOT NULL AUTO_INCREMENT,
  `status` VARCHAR(45) NULL,
  `color_code` VARCHAR(45) NULL,
  PRIMARY KEY (`status_id`)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS `Audit_Log` (
  `audit_log_id` INT NOT NULL AUTO_INCREMENT,
  `task_id` INT NULL,
  `user_id` INT NULL,
  `prev_state` TEXT NULL,
  `new_state` TEXT NULL,
  `table_type` VARCHAR(45) NULL,
  `table_id` INT NULL,
  PRIMARY KEY (`audit_log_id`),
  INDEX `idx_audit_task` (`task_id`),
  INDEX `idx_audit_user` (`user_id`)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS `Timestamps` (
  `ts_id` INT NOT NULL AUTO_INCREMENT,
  `create_time` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  `update_time` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  `audit_log_id` INT NOT NULL,
  PRIMARY KEY (`ts_id`),
  INDEX `idx_ts_audit_log` (`audit_log_id`),
  INDEX `idx_ts_create_time` (`create_time`)         
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS `Users` (
  `user_id` INT NOT NULL AUTO_INCREMENT,
  `username` VARCHAR(32) NULL,
  `email` VARCHAR(255) NOT NULL,
  `password` VARCHAR(255) CHARACTER SET 'ascii' NOT NULL,
  `is_admin` TINYINT(1) DEFAULT 0,
  `first_name` VARCHAR(64) NOT NULL,
  `last_name` VARCHAR(64) NOT NULL,
  `ts_id` INT NULL,
  `color_code` VARCHAR(45) NULL,
  `is_deleted` TINYINT(1) DEFAULT 0,
  `is_invited` TINYINT(1) DEFAULT 0,
  `invitation_key_id` INT NULL,
  `security_question` VARCHAR(255),
  `security_answer_hash` VARCHAR(255),
  PRIMARY KEY (`user_id`),
  UNIQUE KEY `username_UNIQUE` (`username`),
  UNIQUE KEY `email_UNIQUE` (`email`),
  INDEX `idx_user_ts` (`ts_id`),
  INDEX `idx_user_invitation_key` (`invitation_key_id`)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS `Invitation_Keys` (
    `key_id` INT NOT NULL AUTO_INCREMENT,
    `key_value` VARCHAR(64) NOT NULL,
    `is_used` TINYINT(1) NOT NULL DEFAULT 0,
    `created_by_user_id` INT NOT NULL,
    `used_by_user_id` INT NULL,
    `created_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
    `used_at` TIMESTAMP NULL,
    PRIMARY KEY (`key_id`),
    UNIQUE KEY `key_value_UNIQUE` (`key_value`),
    INDEX `idx_key_created_by` (`created_by_user_id`),
    INDEX `idx_key_used_by` (`used_by_user_id`),
    CONSTRAINT `fk_Key_Created_By`
    FOREIGN KEY (`created_by_user_id`) REFERENCES `Users` (`user_id`)
    ON DELETE NO ACTION ON UPDATE NO ACTION,
    CONSTRAINT `fk_Key_Used_By`
    FOREIGN KEY (`used_by_user_id`) REFERENCES `Users` (`user_id`)
    ON DELETE NO ACTION ON UPDATE NO ACTION
    ) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS `Recurring_Task` (
  `recurring_task_id` INT NOT NULL AUTO_INCREMENT,
  `step_id`           INT NOT NULL,
  `day_of_month`      TINYINT NOT NULL,    -- e.g., 10 → “10th of every month”
  `title`             VARCHAR(255) NOT NULL,
  `notes`             TEXT NULL,
  `is_active`         TINYINT(1) NOT NULL DEFAULT 1,
  PRIMARY KEY (`recurring_task_id`),
  INDEX `idx_rec_step` (`step_id`),
  CONSTRAINT `fk_rec_step`
    FOREIGN KEY (`step_id`) REFERENCES `Step` (`step_id`)
    ON DELETE CASCADE ON UPDATE NO ACTION
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS `Task` (
  `task_id` INT NOT NULL AUTO_INCREMENT,
  `recurring_task_id` INT NULL,
  `due_date` DATE NULL,
  `ts_id` INT NOT NULL,
  `user_id` INT NULL,
  `step_id` INT NOT NULL,
  `status_id` INT NOT NULL,
  `is_deleted` TINYINT(1) NOT NULL DEFAULT 0,  
  `is_recurring` TINYINT(1) NOT NULL DEFAULT 1,  
  `title` VARCHAR(255) NOT NULL,
  `notes` TEXT NULL,                         
  PRIMARY KEY (`task_id`),
  INDEX `idx_task_user` (`user_id`),
  INDEX `idx_task_step` (`step_id`),
  INDEX `idx_task_status` (`status_id`),
  INDEX `idx_task_ts` (`ts_id`),
  INDEX `idx_task_is_deleted` (`is_deleted`),   
  INDEX `idx_task_is_recurring` (`is_recurring`),
  INDEX `idx_task_recurring` (`recurring_task_id`)
) ENGINE=InnoDB;


CREATE TABLE IF NOT EXISTS `Comments` (
  `comment_id` INT NOT NULL AUTO_INCREMENT,
  `user_id` INT NOT NULL,
  `task_id` INT NOT NULL,
  `ts_id` INT NOT NULL,
  `comment` TEXT NULL,
  PRIMARY KEY (`comment_id`),
  INDEX `idx_comment_user` (`user_id`),
  INDEX `idx_comment_task` (`task_id`),
  INDEX `idx_comment_ts` (`ts_id`)
) ENGINE=InnoDB;

-- NEW: Per-user read marker for each task (supports unread indicators)
CREATE TABLE IF NOT EXISTS `User_Task_Read_Markers` (
  `user_id` INT NOT NULL,
  `task_id` INT NOT NULL,
  `last_read_ts` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`user_id`, `task_id`)
) ENGINE=InnoDB;

-- =========================
-- Phase 2: Add Foreign Keys
-- =========================

ALTER TABLE `Step`
  ADD CONSTRAINT `fk_Step_Dashboard`
    FOREIGN KEY (`dashboard_id`) REFERENCES `Dashboard` (`dashboard_id`)
    ON DELETE NO ACTION ON UPDATE NO ACTION,
  ADD CONSTRAINT `fk_Step_Business_Day`
    FOREIGN KEY (`business_day_id`) REFERENCES `Business_Day` (`business_day_id`)
    ON DELETE NO ACTION ON UPDATE NO ACTION;

ALTER TABLE `Timestamps`
  ADD CONSTRAINT `fk_Timestamps_Audit_Log`
    FOREIGN KEY (`audit_log_id`) REFERENCES `Audit_Log` (`audit_log_id`)
    ON DELETE NO ACTION ON UPDATE NO ACTION;

ALTER TABLE `Users`
  ADD CONSTRAINT `fk_Users_Timestamps`
    FOREIGN KEY (`ts_id`) REFERENCES `Timestamps` (`ts_id`)
    ON DELETE NO ACTION ON UPDATE NO ACTION,
  ADD CONSTRAINT `fk_Users_Invitation_Key`
    FOREIGN KEY (`invitation_key_id`) REFERENCES `Invitation_Keys` (`key_id`)
    ON DELETE NO ACTION ON UPDATE NO ACTION;

ALTER TABLE `Task`
  ADD CONSTRAINT `fk_Task_Users`
    FOREIGN KEY (`user_id`) REFERENCES `Users` (`user_id`)
    ON DELETE NO ACTION ON UPDATE NO ACTION,
  ADD CONSTRAINT `fk_Task_Step`
    FOREIGN KEY (`step_id`) REFERENCES `Step` (`step_id`)
    ON DELETE NO ACTION ON UPDATE NO ACTION,
  ADD CONSTRAINT `fk_Task_Status`
    FOREIGN KEY (`status_id`) REFERENCES `Status` (`status_id`)
    ON DELETE NO ACTION ON UPDATE NO ACTION,
  ADD CONSTRAINT `fk_Task_Timestamps`
    FOREIGN KEY (`ts_id`) REFERENCES `Timestamps` (`ts_id`)
    ON DELETE NO ACTION ON UPDATE NO ACTION,
  ADD CONSTRAINT `fk_Task_Recurring`
    FOREIGN KEY (`recurring_task_id`) REFERENCES `Recurring_Task` (`recurring_task_id`)
    ON DELETE SET NULL ON UPDATE NO ACTION;


ALTER TABLE `Audit_Log`
  ADD CONSTRAINT `fk_Audit_Log_Task`
    FOREIGN KEY (`task_id`) REFERENCES `Task` (`task_id`)
    ON DELETE NO ACTION ON UPDATE NO ACTION,
  ADD CONSTRAINT `fk_Audit_Log_Users`
    FOREIGN KEY (`user_id`) REFERENCES `Users` (`user_id`)
    ON DELETE NO ACTION ON UPDATE NO ACTION;

ALTER TABLE `Comments`
  ADD CONSTRAINT `fk_Comments_Users`
    FOREIGN KEY (`user_id`) REFERENCES `Users` (`user_id`)
    ON DELETE NO ACTION ON UPDATE NO ACTION,
  ADD CONSTRAINT `fk_Comments_Task`
    FOREIGN KEY (`task_id`) REFERENCES `Task` (`task_id`)
    ON DELETE NO ACTION ON UPDATE NO ACTION,
  ADD CONSTRAINT `fk_Comments_Timestamps`
    FOREIGN KEY (`ts_id`) REFERENCES `Timestamps` (`ts_id`)
    ON DELETE NO ACTION ON UPDATE NO ACTION;

-- NEW: Read marker FKs (cascade so rows clean up with their parents)
ALTER TABLE `User_Task_Read_Markers`
  ADD CONSTRAINT `fk_ReadMarkers_User`
    FOREIGN KEY (`user_id`) REFERENCES `Users` (`user_id`)
    ON DELETE CASCADE ON UPDATE NO ACTION,
  ADD CONSTRAINT `fk_ReadMarkers_Task`
    FOREIGN KEY (`task_id`) REFERENCES `Task` (`task_id`)
    ON DELETE CASCADE ON UPDATE NO ACTION;

SET SQL_MODE=@OLD_SQL_MODE;
SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS;
SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS;
