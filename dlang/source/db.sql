CREATE TABLE "user"
(
    id UUID NOT NULL PRIMARY KEY,
    email VARCHAR(128) NOT NULL UNIQUE,
    sha BYTEA(140),
    pbkdf2 BYTEA(256),
    checkInterval INT NULL
);

CREATE TABLE feed
(
    id UUID NOT NULL PRIMARY KEY,
    url VARCHAR(256),
    title VARCHAR(256),
    iconURL VARCHAR(256),
    checkInterval INT,
    nextRead TIMESTAMP NOT NULL,
    lastRead TIMESTAMP NOT NULL DEFAULT '1970-01-01',
    errors INT NOT NULL DEFAULT 0
);

CREATE TABLE article
(
    id UUID NOT NULL PRIMARY KEY,
    feedId INT NOT NULL REFERENCES feed(id),
    url VARCHAR(256) NOT NULL,
    title VARCHAR(256),
    description TEXT,
    publishDate TIMESTAMP NOT NULL
);

CREATE TABLE subscription
(
    userId UUID NOT NULL REFERENCES "user"(id),
    feedId UUID NOT NULL REFERENCES feed(id),
    PRIMARY KEY (userId, feedId)
);

CREATE TABLE read
(
    userId UUID NOT NULL REFERENCES "user"(id),
    feedId UUID NOT NULL REFERENCES feed(id),
    articleId UUID NOT NULL REFERENCES article(id),
    PRIMARY KEY (userId, articleId)
);

/*
-- Maybe?
CREATE TABLE session
(
    id UUID NOT NULL PRIMARY KEY,
    userId UUID NOT NULL REFERENCES "user"(id),
    expires TIMESTAMP NOT NULL
);
*/


CREATE INDEX idx_article_feedDate ON article (feedId, publishDate);
