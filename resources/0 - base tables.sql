CREATE TABLE users
(
    id CHAR(36) NOT NULL PRIMARY KEY,
    email TEXT NOT NULL UNIQUE,
    sha TEXT,
    pbkdf2 TEXT,
    checkInterval INT NULL,
    created TIMESTAMP NOT NULL DEFAULT now()
);

CREATE TABLE feeds
(
    id CHAR(36) NOT NULL PRIMARY KEY,
    url TEXT,
    title TEXT,
    iconURL TEXT,
    checkInterval INT,
    nextRead TIMESTAMP NOT NULL,
    lastRead TIMESTAMP NOT NULL DEFAULT '1970-01-01',
    errors INT NOT NULL DEFAULT 0,
    created TIMESTAMP NOT NULL DEFAULT now()
);

CREATE TABLE articles
(
    id CHAR(36) NOT NULL PRIMARY KEY,
    feedId CHAR(36) NOT NULL REFERENCES feeds(id) ON DELETE CASCADE,
    url TEXT NOT NULL,
    title TEXT,
    description TEXT,
    author TEXT,
    internalId TEXT,
    publishDate TIMESTAMP NOT NULL,
    readDate TIMESTAMP NOT NULL,
    created TIMESTAMP NOT NULL DEFAULT now()
);

CREATE TABLE subscriptions
(
    userId CHAR(36) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    -- We shouldn't delete a feed while there are active subscriptions.
    feedId CHAR(36) NOT NULL REFERENCES feeds(id),
    title TEXT NULL,
    labels TEXT NULL,
    created TIMESTAMP NOT NULL DEFAULT now(),
    PRIMARY KEY (userId, feedId)
);

CREATE TABLE read
(
    userId CHAR(36) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    feedId CHAR(36) NOT NULL REFERENCES feeds(id) ON DELETE CASCADE,
    articleId CHAR(36) NOT NULL REFERENCES articles(id) ON DELETE CASCADE,
    created TIMESTAMP NOT NULL DEFAULT now(),
    PRIMARY KEY (userId, articleId)
);

CREATE TABLE sessions
(
    id CHAR(36) NOT NULL PRIMARY KEY,
    userId CHAR(36) NOT NULL REFERENCES "users"(id) ON DELETE CASCADE,
    expires TIMESTAMP NOT NULL,
    created TIMESTAMP NOT NULL DEFAULT now()
);

CREATE INDEX idx_article_feedDate ON articles (feedId, publishDate);

