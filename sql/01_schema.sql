-- ============================================================================
-- SingleStore Schema for Hacker News Real-Time Semantic Search
-- ============================================================================
-- This script creates the database schema for ingesting Hacker News stories
-- and comments with automatic vector embedding generation using EMBED_TEXT()
--
-- Prerequisites:
--   - SingleStore workspace with AI Functions installed
--   - Sufficient compute resources for vector operations
-- ============================================================================

-- Create database
CREATE DATABASE IF NOT EXISTS hackernews_semantic;
USE hackernews_semantic;

-- ============================================================================
-- Main Stories Table
-- ============================================================================
-- Stores Hacker News stories with vector embeddings for semantic search
-- title_embedding: Vector embedding of just the title (fast, focused)
-- combined_embedding: Vector embedding of title + text (comprehensive)
-- ============================================================================

CREATE TABLE IF NOT EXISTS hn_stories (
    -- Primary identifiers
    id BIGINT PRIMARY KEY,
    
    -- Story metadata
    title TEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
    url TEXT,
    score INT DEFAULT 0,
    `by` VARCHAR(255),
    time DATETIME,
    descendants INT DEFAULT 0,  -- Number of comments
    type VARCHAR(50),  -- 'story', 'ask', 'show', etc.
    
    -- Story content
    text LONGTEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
    
    -- Vector embeddings (1536 dimensions for OpenAI text-embedding-3-small)
    title_embedding VECTOR(1536),
    combined_embedding VECTOR(1536),
    
    -- Tracking
    created_at DATETIME DEFAULT NOW(),
    updated_at DATETIME DEFAULT NOW() ON UPDATE NOW(),
    
    -- Indexes for performance
    SORT KEY (time DESC, score DESC),
    KEY idx_score (score),
    KEY idx_by (`by`),
    KEY idx_type (type),
    KEY idx_created_at (created_at)
) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;

-- Vector indexes for fast similarity search
-- IVF_PQFS is recommended for production use
ALTER TABLE hn_stories 
ADD VECTOR INDEX ivf_stories_title (title_embedding) 
INDEX_OPTIONS '{"index_type":"IVF_PQFS"}';

ALTER TABLE hn_stories 
ADD VECTOR INDEX ivf_stories_combined (combined_embedding) 
INDEX_OPTIONS '{"index_type":"IVF_PQFS"}';

-- ============================================================================
-- Comments Table
-- ============================================================================
-- Stores Hacker News comments with vector embeddings for semantic search
-- Sharded by story_id for efficient retrieval of all comments for a story
-- ============================================================================

CREATE TABLE IF NOT EXISTS hn_comments (
    -- Primary identifiers
    id BIGINT,
    
    -- Relationship
    parent_id BIGINT,  -- Parent comment or story
    story_id BIGINT,   -- Top-level story
    
    -- Comment metadata
    `by` VARCHAR(255),
    time DATETIME,
    type VARCHAR(50) DEFAULT 'comment',
    
    -- Comment content
    text LONGTEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
    
    -- Vector embedding
    text_embedding VECTOR(1536),
    
    -- Tracking
    created_at DATETIME DEFAULT NOW(),
    updated_at DATETIME DEFAULT NOW() ON UPDATE NOW(),
    
    -- PRIMARY KEY must include shard key in SingleStore
    PRIMARY KEY (id, story_id),
    
    -- Indexes
    SHARD KEY (story_id),
    KEY idx_parent (parent_id),
    KEY idx_story (story_id),
    KEY idx_by (`by`),
    KEY idx_time (time),
    KEY idx_created_at (created_at)
) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;

-- Vector index for semantic search on comments
ALTER TABLE hn_comments 
ADD VECTOR INDEX ivf_comments (text_embedding) 
INDEX_OPTIONS '{"index_type":"IVF_PQFS"}';

-- ============================================================================
-- Staging Tables (for pipeline ingestion before embedding)
-- ============================================================================
-- These tables receive raw data from Kafka pipelines
-- Stored procedures then process them, generate embeddings, and insert to main tables
-- ============================================================================

CREATE TABLE IF NOT EXISTS hn_stories_staging (
    id BIGINT,
    title TEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
    url TEXT,
    score INT,
    `by` VARCHAR(255),
    time DATETIME,
    descendants INT,
    type VARCHAR(50),
    text LONGTEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
    created_at DATETIME DEFAULT NOW(),
    
    KEY idx_created_at (created_at)
) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;

CREATE TABLE IF NOT EXISTS hn_comments_staging (
    id BIGINT,
    parent_id BIGINT,
    story_id BIGINT,
    `by` VARCHAR(255),
    time DATETIME,
    type VARCHAR(50),
    text LONGTEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
    created_at DATETIME DEFAULT NOW(),
    
    KEY idx_created_at (created_at)
) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;

-- ============================================================================
-- Statistics and Monitoring Table
-- ============================================================================
-- Tracks ingestion metrics for monitoring dashboard
-- ============================================================================

CREATE TABLE IF NOT EXISTS ingestion_stats (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    stat_type VARCHAR(50),  -- 'stories', 'comments'
    batch_size INT,
    processing_time_ms INT,
    embeddings_generated INT,
    errors_count INT,
    timestamp DATETIME DEFAULT NOW(),
    
    KEY idx_timestamp (timestamp),
    KEY idx_stat_type (stat_type)
);

-- ============================================================================
-- Semantic Search Cache (Optional - for frequently searched terms)
-- ============================================================================
-- Caches query embeddings to avoid regenerating them
-- ============================================================================

CREATE TABLE IF NOT EXISTS search_cache (
    query_text VARCHAR(500) PRIMARY KEY,
    query_embedding VECTOR(1536),
    hit_count INT DEFAULT 1,
    last_used DATETIME DEFAULT NOW() ON UPDATE NOW(),
    created_at DATETIME DEFAULT NOW(),
    
    KEY idx_last_used (last_used)
) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;

-- ============================================================================
-- Views for Monitoring
-- ============================================================================

-- View: Recent ingestion activity
DROP VIEW IF EXISTS v_recent_activity;
CREATE VIEW v_recent_activity AS
SELECT 
    'story' AS item_type,
    id,
    title AS content_preview,
    `by` AS author,
    score,
    created_at
FROM hn_stories
UNION ALL
SELECT 
    'comment' AS item_type,
    id,
    LEFT(text, 100) AS content_preview,
    `by` AS author,
    NULL AS score,
    created_at
FROM hn_comments
ORDER BY created_at DESC
LIMIT 100;

-- View: Ingestion rate statistics
DROP VIEW IF EXISTS v_ingestion_rates;
CREATE VIEW v_ingestion_rates AS
SELECT 
    DATE_FORMAT(created_at, '%Y-%m-%d %H:%i:00') AS minute,
    COUNT(*) AS stories_per_minute
FROM hn_stories
WHERE created_at >= NOW() - INTERVAL 1 HOUR
GROUP BY minute
UNION ALL
SELECT 
    DATE_FORMAT(created_at, '%Y-%m-%d %H:%i:00') AS minute,
    COUNT(*) AS comments_per_minute
FROM hn_comments
WHERE created_at >= NOW() - INTERVAL 1 HOUR
GROUP BY minute
ORDER BY minute DESC;

-- View: Top stories by score
DROP VIEW IF EXISTS v_top_stories;
CREATE VIEW v_top_stories AS
SELECT 
    id,
    title,
    url,
    score,
    `by`,
    descendants,
    time,
    created_at
FROM hn_stories
WHERE title_embedding IS NOT NULL
ORDER BY score DESC, time DESC
LIMIT 100;

-- ============================================================================
-- Grant permissions (adjust as needed for your user)
-- ============================================================================
-- Note: Replace 'your_user' with your actual username
-- GRANT SELECT, INSERT, UPDATE, DELETE ON hackernews_semantic.* TO 'your_user'@'%';

-- ============================================================================
-- Schema creation complete!
-- Next steps:
--   1. Run 02_procedures.sql to create stored procedures
--   2. Run 03_pipelines.sql to create pipelines
--   3. Start the data fetcher to begin ingestion
-- ============================================================================

SELECT 'Schema created successfully!' AS status;
SELECT 'Tables created:' AS info, COUNT(*) AS table_count 
FROM information_schema.TABLES 
WHERE table_schema = 'hackernews_semantic';
