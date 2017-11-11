DROP TABLE users, feeds, articles, subscriptions, read;
CREATE TABLE users
(
    id CHAR(36) NOT NULL PRIMARY KEY,
    email TEXT NOT NULL UNIQUE,
    sha TEXT,
    pbkdf2 TEXT,
    checkInterval INT NULL
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
    errors INT NOT NULL DEFAULT 0
);

CREATE TABLE articles
(
    id CHAR(36) NOT NULL PRIMARY KEY,
    feedId CHAR(36) NOT NULL REFERENCES feeds(id),
    url TEXT NOT NULL,
    title TEXT,
    description TEXT,
    author TEXT,
    internalId TEXT,
    publishDate TIMESTAMP NOT NULL
);

CREATE TABLE subscriptions
(
    userId CHAR(36) NOT NULL REFERENCES users(id),
    feedId CHAR(36) NOT NULL REFERENCES feeds(id),
    PRIMARY KEY (userId, feedId)
);

CREATE TABLE read
(
    userId CHAR(36) NOT NULL REFERENCES users(id),
    feedId CHAR(36) NOT NULL REFERENCES feeds(id),
    articleId CHAR(36) NOT NULL REFERENCES articles(id),
    PRIMARY KEY (userId, articleId)
);

CREATE TABLE sessions
(
    id CHAR(36) NOT NULL PRIMARY KEY,
    userId CHAR(36) NOT NULL REFERENCES "users"(id),
    expires TIMESTAMP NOT NULL
);


CREATE INDEX idx_article_feedDate ON articles (feedId, publishDate);
