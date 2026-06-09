local DB = {}
local fmt = string.format

function DB.query(sql, params) return MySQL.query.await(sql, params or {}) end
function DB.single(sql, params) return MySQL.single.await(sql, params or {}) end
function DB.insert(sql, params) return MySQL.insert.await(sql, params or {}) end
function DB.exec(sql, params) return MySQL.query.await(sql, params or {}) end

local function columnExists(tableName, columnName)
  local rows = DB.query([[SELECT 1
    FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?
    LIMIT 1
  ]], { tableName, columnName })
  return rows and rows[1] ~= nil
end

local function ensureColumn(tableName, columnName, definition)
  if not columnExists(tableName, columnName) then
    DB.exec(fmt('ALTER TABLE %s ADD COLUMN %s %s', tableName, columnName, definition))
  end
end

local function indexExists(tableName, indexName)
  local rows = DB.query([[SELECT 1
    FROM information_schema.STATISTICS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND INDEX_NAME = ?
    LIMIT 1
  ]], { tableName, indexName })
  return rows and rows[1] ~= nil
end

local function dropIndex(tableName, indexName)
  if indexExists(tableName, indexName) then
    DB.exec(fmt('ALTER TABLE %s DROP INDEX %s', tableName, indexName))
  end
end

local function ensureUniqueKey(tableName, indexName, columns)
  if not indexExists(tableName, indexName) then
    DB.exec(fmt('ALTER TABLE %s ADD UNIQUE KEY %s (%s)', tableName, indexName, columns))
  end
end

local function constraintExists(tableName, constraintName)
  local rows = DB.query([[SELECT 1
    FROM information_schema.TABLE_CONSTRAINTS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND CONSTRAINT_NAME = ?
    LIMIT 1
  ]], { tableName, constraintName })
  return rows and rows[1] ~= nil
end

local function dropConstraint(tableName, constraintName)
  if constraintExists(tableName, constraintName) then
    DB.exec(fmt('ALTER TABLE %s DROP FOREIGN KEY %s', tableName, constraintName))
  end
end

local function ensureForeignKey(tableName, constraintName, columnList, referencedTable, referencedColumns, options)
  if constraintExists(tableName, constraintName) then return end
  local clause = fmt('FOREIGN KEY (%s) REFERENCES %s (%s)', columnList, referencedTable, referencedColumns)
  if options and options ~= '' then
    clause = clause .. ' ' .. options
  end
  DB.exec(fmt('ALTER TABLE %s ADD CONSTRAINT %s %s', tableName, constraintName, clause))
end

function DB.runMigrations()
  DB.exec([[CREATE TABLE IF NOT EXISTS exec_players (
  id INT AUTO_INCREMENT PRIMARY KEY,
  citizenid VARCHAR(64) NOT NULL,
  license VARCHAR(64) DEFAULT '',
  char_id VARCHAR(64) DEFAULT '',
  display_name VARCHAR(64) NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uniq_citizenid (citizenid)
);]])

  DB.exec([[CREATE TABLE IF NOT EXISTS exec_stats (
  id INT AUTO_INCREMENT PRIMARY KEY,
  citizenid VARCHAR(64) NOT NULL,
  license VARCHAR(64) DEFAULT '',
  char_id VARCHAR(64) DEFAULT '',
  mode VARCHAR(32) NOT NULL,
  kills INT DEFAULT 0,
  deaths INT DEFAULT 0,
  wins INT DEFAULT 0,
  losses INT DEFAULT 0,
  last_played TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uniq_citizen_mode (citizenid, mode)
);]])

  DB.exec([[CREATE TABLE IF NOT EXISTS exec_matches (
  id INT AUTO_INCREMENT PRIMARY KEY,
  mode VARCHAR(32) NOT NULL,
  bracket VARCHAR(16) NOT NULL,
  location VARCHAR(32) NOT NULL,
  bucket INT NOT NULL,
  started_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  ended_at TIMESTAMP NULL,
  winner_json JSON NULL
);]])

  DB.exec([[CREATE TABLE IF NOT EXISTS exec_gangs (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(64) NOT NULL,
    leader_citizenid VARCHAR(64) NOT NULL,
    leader_license VARCHAR(64) DEFAULT '',
    leader_char VARCHAR(64) DEFAULT '',
    strikes INT DEFAULT 0,
    wins INT DEFAULT 0,
    losses INT DEFAULT 0,
    active TINYINT(1) DEFAULT 1,
    rank_labels JSON NULL,
    underboss_perms JSON NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
  );]])

  DB.exec([[CREATE TABLE IF NOT EXISTS exec_gangmembers (
    id INT AUTO_INCREMENT PRIMARY KEY,
    gang_id INT NOT NULL,
    citizenid VARCHAR(64) NOT NULL,
    license VARCHAR(64) DEFAULT '',
    char_id VARCHAR(64) DEFAULT '',
    member_name VARCHAR(64) DEFAULT '',
    rank VARCHAR(16) NOT NULL,
    wins INT DEFAULT 0,
    losses INT DEFAULT 0,
    kills INT DEFAULT 0,
    deaths INT DEFAULT 0,
    joined_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_active TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_gang FOREIGN KEY (gang_id) REFERENCES exec_gangs(id) ON DELETE CASCADE,
    UNIQUE KEY uniq_member_citizen (gang_id, citizenid)
  );]])

  DB.exec([[CREATE TABLE IF NOT EXISTS exec_stat_profiles (
    id INT AUTO_INCREMENT PRIMARY KEY,
    entity_type ENUM('player','gang') NOT NULL,
    entity_id VARCHAR(64) NOT NULL,
    entity_name VARCHAR(64) NOT NULL,
    mode VARCHAR(32) NOT NULL,
    metrics JSON NOT NULL,
    captured_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uniq_stat_entity_mode (entity_type, entity_id, mode)
  );]])

  DB.exec([[CREATE TABLE IF NOT EXISTS exec_stat_awards (
    id INT AUTO_INCREMENT PRIMARY KEY,
    award_key VARCHAR(32) NOT NULL,
    entity_type ENUM('player','gang','global') NOT NULL,
    entity_id VARCHAR(64) NOT NULL,
    entity_name VARCHAR(64) NOT NULL,
    value DOUBLE NOT NULL DEFAULT 0,
    extra JSON NULL,
    captured_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uniq_award_entity (award_key, entity_type, entity_id)
  );]])

  DB.exec([[CREATE TABLE IF NOT EXISTS exec_unique (
    key_name VARCHAR(64) PRIMARY KEY,
    value JSON NULL,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
  );]])

  DB.exec([[CREATE TABLE IF NOT EXISTS exec_weapon_unlocks (
    id INT AUTO_INCREMENT PRIMARY KEY,
    license VARCHAR(64) NOT NULL,
    weapon_code VARCHAR(64) NOT NULL,
    tebex_sku VARCHAR(64) DEFAULT NULL,
    unlocked TINYINT(1) NOT NULL DEFAULT 1,
    meta JSON NULL,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uniq_license_weapon (license, weapon_code)
  );]])

  ensureColumn('exec_stats', 'time_played', 'INT NOT NULL DEFAULT 0')

  ensureColumn('exec_players', 'citizenid', "VARCHAR(64) NOT NULL DEFAULT ''")
  ensureColumn('exec_players', 'license', "VARCHAR(64) DEFAULT ''")
  ensureColumn('exec_players', 'char_id', "VARCHAR(64) DEFAULT ''")
  DB.exec([[UPDATE exec_players
    SET citizenid = CASE
      WHEN citizenid IS NULL OR citizenid = '' OR citizenid = 'default' THEN
        CASE
          WHEN license IS NOT NULL AND license <> '' THEN license
          ELSE CONCAT('legacy_player_', id)
        END
      ELSE citizenid
    END
  ]])
  DB.exec([[UPDATE exec_players
    SET char_id = CASE
      WHEN char_id IS NULL OR char_id = '' OR char_id = 'default' THEN citizenid
      ELSE char_id
    END
  ]])
  dropIndex('exec_players', 'uniq_license_char')
  ensureUniqueKey('exec_players', 'uniq_citizenid', 'citizenid')

  ensureColumn('exec_stats', 'citizenid', "VARCHAR(64) NOT NULL DEFAULT ''")
  ensureColumn('exec_stats', 'license', "VARCHAR(64) DEFAULT ''")
  ensureColumn('exec_stats', 'char_id', "VARCHAR(64) DEFAULT ''")
  DB.exec([[UPDATE exec_stats
    SET citizenid = CASE
      WHEN citizenid IS NULL OR citizenid = '' OR citizenid = 'default' THEN
        CASE
          WHEN license IS NOT NULL AND license <> '' THEN license
          ELSE CONCAT('legacy_stat_', id)
        END
      ELSE citizenid
    END
  ]])
  DB.exec([[UPDATE exec_stats
    SET char_id = CASE
      WHEN char_id IS NULL OR char_id = '' OR char_id = 'default' THEN citizenid
      ELSE char_id
    END
  ]])
  dropIndex('exec_stats', 'uniq_player_mode')
  ensureUniqueKey('exec_stats', 'uniq_citizen_mode', 'citizenid, mode')

  ensureColumn('exec_gangs', 'leader_citizenid', "VARCHAR(64) NOT NULL DEFAULT ''")
  ensureColumn('exec_gangs', 'leader_license', "VARCHAR(64) DEFAULT ''")
  ensureColumn('exec_gangs', 'leader_char', "VARCHAR(64) DEFAULT ''")
  ensureColumn('exec_gangs', 'strikes', 'INT DEFAULT 0')
  ensureColumn('exec_gangs', 'wins', 'INT DEFAULT 0')
  ensureColumn('exec_gangs', 'losses', 'INT DEFAULT 0')
  ensureColumn('exec_gangs', 'active', 'TINYINT(1) DEFAULT 1')
  ensureColumn('exec_gangs', 'rank_labels', 'JSON NULL')
  ensureColumn('exec_gangs', 'underboss_perms', 'JSON NULL')
  ensureColumn('exec_gangs', 'updated_at', 'TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP')
  DB.exec([[UPDATE exec_gangs
    SET leader_citizenid = CASE
      WHEN leader_citizenid IS NULL OR leader_citizenid = '' OR leader_citizenid = 'default' THEN
        CASE
          WHEN leader_license IS NOT NULL AND leader_license <> '' THEN leader_license
          ELSE CONCAT('legacy_gang_leader_', id)
        END
      ELSE leader_citizenid
    END,
    leader_char = CASE
      WHEN leader_char IS NULL OR leader_char = '' OR leader_char = 'default' THEN
        CASE
          WHEN leader_license IS NOT NULL AND leader_license <> '' THEN leader_license
          ELSE CONCAT('legacy_gang_leader_', id)
        END
      ELSE leader_char
    END
  ]])

  ensureColumn('exec_gangmembers', 'citizenid', "VARCHAR(64) NOT NULL DEFAULT ''")
  ensureColumn('exec_gangmembers', 'license', "VARCHAR(64) DEFAULT ''")
  ensureColumn('exec_gangmembers', 'char_id', "VARCHAR(64) DEFAULT ''")
  ensureColumn('exec_gangmembers', 'member_name', "VARCHAR(64) DEFAULT ''")
  ensureColumn('exec_gangmembers', 'rank', "VARCHAR(16) NOT NULL DEFAULT 'footsoldier'")
  ensureColumn('exec_gangmembers', 'wins', 'INT DEFAULT 0')
  ensureColumn('exec_gangmembers', 'losses', 'INT DEFAULT 0')
  ensureColumn('exec_gangmembers', 'kills', 'INT DEFAULT 0')
  ensureColumn('exec_gangmembers', 'deaths', 'INT DEFAULT 0')
  ensureColumn('exec_gangmembers', 'joined_at', 'TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP')
  ensureColumn('exec_gangmembers', 'last_active', 'TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP')
  DB.exec([[UPDATE exec_gangmembers
    SET citizenid = CASE
      WHEN citizenid IS NULL OR citizenid = '' OR citizenid = 'default' THEN
        CASE
          WHEN license IS NOT NULL AND license <> '' THEN license
          ELSE CONCAT('legacy_member_', id)
        END
      ELSE citizenid
    END
  ]])
  DB.exec([[UPDATE exec_gangmembers
    SET char_id = CASE
      WHEN char_id IS NULL OR char_id = '' OR char_id = 'default' THEN citizenid
      ELSE char_id
    END
  ]])
  dropConstraint('exec_gangmembers', 'fk_gang')
  dropIndex('exec_gangmembers', 'uniq_member')
  ensureUniqueKey('exec_gangmembers', 'uniq_member_citizen', 'gang_id, citizenid')
  ensureForeignKey('exec_gangmembers', 'fk_gang', 'gang_id', 'exec_gangs', 'id', 'ON DELETE CASCADE')

  ensureUniqueKey('exec_weapon_unlocks', 'uniq_license_weapon', 'license, weapon_code')
end

return DB
