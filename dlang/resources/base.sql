CREATE TABLE IF NOT EXISTS migrations
(
    name TEXT NOT NULL PRIMARY KEY,
    script TEXT,
    applied TIMESTAMP
);

