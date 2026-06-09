-- EXEC Framework database schema
-- Run these statements once on your server database before starting the resource.

CREATE TABLE IF NOT EXISTS `exec_players` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `citizenid` VARCHAR(64) NOT NULL,
  `license` VARCHAR(64) DEFAULT '',
  `char_id` VARCHAR(64) DEFAULT '',
  `display_name` VARCHAR(64) NOT NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY `uniq_citizenid` (`citizenid`)
);

CREATE TABLE IF NOT EXISTS `exec_stats` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `citizenid` VARCHAR(64) NOT NULL,
  `license` VARCHAR(64) DEFAULT '',
  `char_id` VARCHAR(64) DEFAULT '',
  `mode` VARCHAR(32) NOT NULL,
  `kills` INT NOT NULL DEFAULT 0,
  `deaths` INT NOT NULL DEFAULT 0,
  `wins` INT NOT NULL DEFAULT 0,
  `losses` INT NOT NULL DEFAULT 0,
  `time_played` INT NOT NULL DEFAULT 0,
  `last_played` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY `uniq_citizen_mode` (`citizenid`, `mode`)
);

CREATE TABLE IF NOT EXISTS `exec_matches` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `mode` VARCHAR(32) NOT NULL,
  `bracket` VARCHAR(16) NOT NULL,
  `location` VARCHAR(32) NOT NULL,
  `bucket` INT NOT NULL,
  `started_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  `ended_at` TIMESTAMP NULL,
  `winner_json` JSON NULL
);

CREATE TABLE IF NOT EXISTS `exec_gangs` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `name` VARCHAR(64) NOT NULL,
  `leader_citizenid` VARCHAR(64) NOT NULL,
  `leader_license` VARCHAR(64) DEFAULT '',
  `leader_char` VARCHAR(64) DEFAULT '',
  `strikes` INT NOT NULL DEFAULT 0,
  `wins` INT NOT NULL DEFAULT 0,
  `losses` INT NOT NULL DEFAULT 0,
  `active` TINYINT(1) NOT NULL DEFAULT 1,
  `rank_labels` JSON NULL,
  `underboss_perms` JSON NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS `exec_gangmembers` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `gang_id` INT NOT NULL,
  `citizenid` VARCHAR(64) NOT NULL,
  `license` VARCHAR(64) DEFAULT '',
  `char_id` VARCHAR(64) DEFAULT '',
  `member_name` VARCHAR(64) DEFAULT '',
  `rank` VARCHAR(16) NOT NULL DEFAULT 'footsoldier',
  `wins` INT NOT NULL DEFAULT 0,
  `losses` INT NOT NULL DEFAULT 0,
  `kills` INT NOT NULL DEFAULT 0,
  `deaths` INT NOT NULL DEFAULT 0,
  `joined_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `last_active` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT `fk_gang` FOREIGN KEY (`gang_id`) REFERENCES `exec_gangs` (`id`) ON DELETE CASCADE,
  UNIQUE KEY `uniq_member_citizen` (`gang_id`, `citizenid`)
);

CREATE TABLE IF NOT EXISTS `exec_stat_profiles` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `entity_type` ENUM('player','gang') NOT NULL,
  `entity_id` VARCHAR(64) NOT NULL,
  `entity_name` VARCHAR(64) NOT NULL,
  `mode` VARCHAR(32) NOT NULL,
  `metrics` JSON NOT NULL,
  `captured_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY `uniq_stat_entity_mode` (`entity_type`, `entity_id`, `mode`)
);

CREATE TABLE IF NOT EXISTS `exec_stat_awards` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `award_key` VARCHAR(32) NOT NULL,
  `entity_type` ENUM('player','gang','global') NOT NULL,
  `entity_id` VARCHAR(64) NOT NULL,
  `entity_name` VARCHAR(64) NOT NULL,
  `value` DOUBLE NOT NULL DEFAULT 0,
  `extra` JSON NULL,
  `captured_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY `uniq_award_entity` (`award_key`, `entity_type`, `entity_id`)
);

CREATE TABLE IF NOT EXISTS `exec_unique` (
  `key_name` VARCHAR(64) PRIMARY KEY,
  `value` JSON NULL,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS `exec_weapon_unlocks` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `license` VARCHAR(64) NOT NULL,
  `weapon_code` VARCHAR(64) NOT NULL,
  `tebex_sku` VARCHAR(64) DEFAULT NULL,
  `unlocked` TINYINT(1) NOT NULL DEFAULT 1,
  `meta` JSON NULL,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY `uniq_license_weapon` (`license`, `weapon_code`)
);
