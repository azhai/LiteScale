package main

// Schema is applied on every start; every statement is idempotent.
//
// SQLite is the system of record: batches carry the idempotency key, records
// carry a content-derived uid, and both uniqueness constraints are what make a
// replayed upload a no-op instead of a duplicated row.
SCHEMA_SQL :: `
PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;
PRAGMA busy_timeout = 5000;
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS clients (
	id            TEXT PRIMARY KEY,
	name          TEXT NOT NULL DEFAULT '',
	app_version   TEXT NOT NULL DEFAULT '',
	platform      TEXT NOT NULL DEFAULT '',
	lang          TEXT NOT NULL DEFAULT '',
	token_hash    TEXT NOT NULL DEFAULT '',
	created_at    INTEGER NOT NULL,
	last_seen_at  INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS devices (
	client_id  TEXT NOT NULL,
	id         TEXT NOT NULL,
	name       TEXT NOT NULL DEFAULT '',
	last_seen  INTEGER NOT NULL,
	PRIMARY KEY (client_id, id)
);

CREATE TABLE IF NOT EXISTS members (
	client_id   TEXT NOT NULL,
	id          TEXT NOT NULL,
	name        TEXT NOT NULL,
	avatar      TEXT NOT NULL DEFAULT '',
	color       INTEGER NOT NULL DEFAULT 0,
	updated_at  INTEGER NOT NULL,
	PRIMARY KEY (client_id, id)
);

-- Legacy single goal per client; kept so older app builds keep working.
CREATE TABLE IF NOT EXISTS goals (
	client_id   TEXT PRIMARY KEY,
	member_id   TEXT,
	kg          REAL NOT NULL,
	updated_at  INTEGER NOT NULL
);

-- Per-member height. 0/absent row means "not set".
CREATE TABLE IF NOT EXISTS member_profiles (
	client_id  TEXT NOT NULL,
	member_id  TEXT NOT NULL,
	height_cm  REAL NOT NULL DEFAULT 0,
	updated_at INTEGER NOT NULL,
	PRIMARY KEY (client_id, member_id)
);

-- Gender and birth month (yyyy-MM). Empty strings mean "not set".
CREATE TABLE IF NOT EXISTS member_details (
	client_id  TEXT NOT NULL,
	member_id  TEXT NOT NULL,
	gender     TEXT NOT NULL DEFAULT '',
	birth      TEXT NOT NULL DEFAULT '',
	updated_at INTEGER NOT NULL,
	PRIMARY KEY (client_id, member_id)
);

-- One goal per member per date. actual_kg is the last measurement on that
-- date as computed by the client; the server never derives it from ts_ms
-- because the client's local day is what the user sees.
CREATE TABLE IF NOT EXISTS member_goals (
	client_id  TEXT NOT NULL,
	member_id  TEXT NOT NULL,
	date       TEXT NOT NULL,
	target_kg  REAL NOT NULL,
	actual_kg  REAL NOT NULL DEFAULT 0,
	updated_at INTEGER NOT NULL,
	PRIMARY KEY (client_id, member_id, date)
);

CREATE INDEX IF NOT EXISTS idx_member_goals_client ON member_goals (client_id, date);

CREATE TABLE IF NOT EXISTS measurements (
	uid          TEXT PRIMARY KEY,
	client_id    TEXT NOT NULL,
	member_id    TEXT NOT NULL,
	device_id    TEXT,
	ts_ms        INTEGER NOT NULL,
	kg           REAL NOT NULL,
	received_at  INTEGER NOT NULL,
	batch_id     TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_measurements_client_ts ON measurements (client_id, ts_ms);
CREATE INDEX IF NOT EXISTS idx_measurements_member_ts ON measurements (member_id, ts_ms);

CREATE TABLE IF NOT EXISTS batches (
	id             TEXT PRIMARY KEY,
	client_id      TEXT NOT NULL,
	received_at    INTEGER NOT NULL,
	payload_sha256 TEXT NOT NULL,
	records        INTEGER NOT NULL,
	accepted       INTEGER NOT NULL,
	duplicates     INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_batches_client ON batches (client_id, received_at);
`
