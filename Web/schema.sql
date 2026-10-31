-- Accounts, sign-in sessions and one board per account.
CREATE TABLE IF NOT EXISTS users (
  id TEXT PRIMARY KEY,
  email TEXT NOT NULL UNIQUE,
  salt TEXT NOT NULL,
  hash TEXT NOT NULL,
  failed INTEGER NOT NULL DEFAULT 0,
  locked_until INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS sessions (
  token_hash TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  expires_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS sessions_user ON sessions(user_id);
-- The board JSON (same format as planner.json), gzip-compressed.
-- version goes up by one on every save; saves must name the version they started from.
CREATE TABLE IF NOT EXISTS boards (
  user_id TEXT PRIMARY KEY,
  version INTEGER NOT NULL,
  data BLOB,
  updated_at INTEGER NOT NULL
);
