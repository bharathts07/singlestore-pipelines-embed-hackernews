-- Database and tables for HN semantic search demo
CREATE DATABASE IF NOT EXISTS hackernews_semantic;
USE hackernews_semantic;

-- Stories table
CREATE TABLE IF NOT EXISTS hn_stories (
    id BIGINT PRIMARY KEY,
    title TEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
    url TEXT,
    score INT DEFAULT 0,
    `by` VARCHAR(255),
    time DATETIME,
    descendants INT DEFAULT 0,
    type VARCHAR(50),
    text LONGTEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
    title_embedding VECTOR(2048),
    combined_embedding VECTOR(2048),
    created_at DATETIME DEFAULT NOW(),
    updated_at DATETIME DEFAULT NOW() ON UPDATE NOW(),
    SORT KEY (time DESC, score DESC),
    KEY idx_score (score),
    KEY idx_by (`by`),
    KEY idx_created_at (created_at)
) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;

ALTER TABLE hn_stories ADD VECTOR INDEX ivf_stories_title (title_embedding) INDEX_OPTIONS '{"index_type":"IVF_PQFS"}';
ALTER TABLE hn_stories ADD VECTOR INDEX ivf_stories_combined (combined_embedding) INDEX_OPTIONS '{"index_type":"IVF_PQFS"}';

-- Comments table
CREATE TABLE IF NOT EXISTS hn_comments (
    id BIGINT,
    parent_id BIGINT,
    story_id BIGINT,
    `by` VARCHAR(255),
    time DATETIME,
    type VARCHAR(50) DEFAULT 'comment',
    text LONGTEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
    text_embedding VECTOR(2048),
    created_at DATETIME DEFAULT NOW(),
    updated_at DATETIME DEFAULT NOW() ON UPDATE NOW(),
    PRIMARY KEY (id, story_id),
    SHARD KEY (story_id),
    KEY idx_parent (parent_id),
    KEY idx_story (story_id),
    KEY idx_by (`by`),
    KEY idx_time (time),
    KEY idx_created_at (created_at)
) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;

ALTER TABLE hn_comments ADD VECTOR INDEX ivf_comments (text_embedding) INDEX_OPTIONS '{"index_type":"IVF_PQFS"}';

-- Staging tables
CREATE TABLE IF NOT EXISTS hn_stories_staging (
    id BIGINT,
    title TEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
    url TEXT,
    score INT,
    `by` VARCHAR(255),
    time BIGINT,
    descendants INT,
    type VARCHAR(50),
    text TEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci
);

CREATE TABLE IF NOT EXISTS hn_comments_staging (
    id BIGINT,
    parent_id BIGINT,
    story_id BIGINT,
    `by` VARCHAR(255),
    time BIGINT,
    type VARCHAR(50),
    text TEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci
);

-- Stats and cache
CREATE TABLE IF NOT EXISTS ingestion_stats (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    timestamp DATETIME DEFAULT NOW(),
    stat_type VARCHAR(50),
    batch_size INT,
    processing_time_ms INT,
    embeddings_generated INT,
    errors_count INT,
    KEY idx_timestamp (timestamp),
    KEY idx_stat_type (stat_type)
);

CREATE TABLE IF NOT EXISTS search_cache (
    query_text VARCHAR(500) PRIMARY KEY,
    query_embedding VECTOR(2048),
    created_at DATETIME DEFAULT NOW(),
    hit_count INT DEFAULT 0,
    KEY idx_created (created_at)
);
