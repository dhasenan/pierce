ALTER TABLE articles ADD mongoId VARCHAR(16) NULL;
CREATE INDEX idx_articles_mongoid ON articles (mongoId);
