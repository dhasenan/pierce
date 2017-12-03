ALTER TABLE articles ADD mongoId TEXT NULL;
CREATE INDEX idx_articles_mongoid ON articles (mongoId);
