-- ============================================================================
-- Stored Procedures for Hacker News Semantic Search
-- ============================================================================
-- These procedures process batches from Kafka pipelines and generate
-- vector embeddings using the EMBED_TEXT() AI function
--
-- Prerequisites:
--   - Schema created (01_schema.sql)
--   - AI Functions installed in SingleStore workspace
-- ============================================================================

USE hackernews_semantic;


-- ============================================================================
-- Procedure: process_stories_batch
-- ============================================================================
-- Processes a batch of stories from the Kafka pipeline
-- Generates embeddings for title and combined title+text
-- Inserts into hn_stories table with embeddings
--
-- Parameters:
--   batch: QUERY type containing story data from Kafka
-- ============================================================================

CREATE OR REPLACE PROCEDURE process_stories_batch(
    batch QUERY(
        id BIGINT,
        title TEXT,
        url TEXT,
        score INT,
        `by` VARCHAR(255),
        time BIGINT,  -- Unix timestamp from HN API
        descendants INT,
        type VARCHAR(50),
        text TEXT
    )
) AS
DECLARE
    v_start_time DATETIME;
    v_end_time DATETIME;
    v_batch_size INT;
    v_processing_time_ms INT;
    v_embeddings_generated INT DEFAULT 0;
    v_errors_count INT DEFAULT 0;
BEGIN
    -- Record start time for metrics
    SET v_start_time = NOW();
    SET v_batch_size = (SELECT COUNT(*) FROM batch);
    
    -- Insert stories with generated embeddings
    -- Using INSERT IGNORE to skip duplicates
    INSERT IGNORE INTO hn_stories (
        id,
        title,
        url,
        score,
        `by`,
        time,
        descendants,
        type,
        text,
        title_embedding,
        combined_embedding,
        created_at
    )
    SELECT 
        b.id,
        b.title,
        b.url,
        COALESCE(b.score, 0) AS score,
        b`.by`,
        FROM_UNIXTIME(b.time) AS time,
        COALESCE(b.descendants, 0) AS descendants,
        b.type,
        b.text,
        -- Generate embedding for title
        cluster.EMBED_TEXT(b.title) AS title_embedding,
        -- Generate embedding for combined title + text (if text exists)
        CASE 
            WHEN b.text IS NOT NULL AND LENGTH(TRIM(b.text)) > 0 
            THEN cluster.EMBED_TEXT(CONCAT(b.title, ' ', b.text))
            ELSE cluster.EMBED_TEXT(b.title)
        END AS combined_embedding,
        NOW() AS created_at
    FROM batch b
    WHERE b.title IS NOT NULL 
      AND LENGTH(TRIM(b.title)) > 0;
    
    -- Count embeddings generated (2 per story typically)
    SET v_embeddings_generated = ROW_COUNT() * 2;
    
    -- Record end time and calculate processing time
    SET v_end_time = NOW();
    SET v_processing_time_ms = TIMESTAMPDIFF(MICROSECOND, v_start_time, v_end_time) / 1000;
    
    -- Insert statistics for monitoring
    INSERT INTO ingestion_stats (
        stat_type,
        batch_size,
        processing_time_ms,
        embeddings_generated,
        errors_count,
        timestamp
    ) VALUES (
        'stories',
        v_batch_size,
        v_processing_time_ms,
        v_embeddings_generated,
        v_errors_count,
        v_end_time
    );
    
    -- Log success
    ECHO SELECT CONCAT('Processed ', v_batch_size, ' stories in ', 
                       v_processing_time_ms, 'ms') AS result;
                       
EXCEPTION
    WHEN OTHERS THEN
        -- Log error
        SET v_errors_count = v_errors_count + 1;
        ECHO SELECT CONCAT('Error processing stories batch: ', @@error_message) AS error;
        -- Continue execution - don't fail the entire batch
END;

-- ============================================================================
-- Procedure: process_comments_batch
-- ============================================================================
-- Processes a batch of comments from the Kafka pipeline
-- Generates embeddings for comment text
-- Inserts into hn_comments table with embeddings
--
-- Parameters:
--   batch: QUERY type containing comment data from Kafka
-- ============================================================================

CREATE OR REPLACE PROCEDURE process_comments_batch(
    batch QUERY(
        id BIGINT,
        parent_id BIGINT,
        story_id BIGINT,
        `by` VARCHAR(255),
        time BIGINT,  -- Unix timestamp
        type VARCHAR(50),
        text TEXT
    )
) AS
DECLARE
    v_start_time DATETIME;
    v_end_time DATETIME;
    v_batch_size INT;
    v_processing_time_ms INT;
    v_embeddings_generated INT DEFAULT 0;
    v_errors_count INT DEFAULT 0;
BEGIN
    -- Record start time for metrics
    SET v_start_time = NOW();
    SET v_batch_size = (SELECT COUNT(*) FROM batch);
    
    -- Insert comments with generated embeddings
    -- Using INSERT IGNORE to skip duplicates
    INSERT IGNORE INTO hn_comments (
        id,
        parent_id,
        story_id,
        `by`,
        time,
        type,
        text,
        text_embedding,
        created_at
    )
    SELECT 
        b.id,
        b.parent_id,
        b.story_id,
        b`.by`,
        FROM_UNIXTIME(b.time) AS time,
        COALESCE(b.type, 'comment') AS type,
        b.text,
        -- Generate embedding for comment text
        cluster.EMBED_TEXT(b.text) AS text_embedding,
        NOW() AS created_at
    FROM batch b
    WHERE b.text IS NOT NULL 
      AND LENGTH(TRIM(b.text)) > 0
      AND LENGTH(b.text) < 8000;  -- Skip extremely long comments
    
    SET v_embeddings_generated = ROW_COUNT();
    
    -- Record end time and calculate processing time
    SET v_end_time = NOW();
    SET v_processing_time_ms = TIMESTAMPDIFF(MICROSECOND, v_start_time, v_end_time) / 1000;
    
    -- Insert statistics for monitoring
    INSERT INTO ingestion_stats (
        stat_type,
        batch_size,
        processing_time_ms,
        embeddings_generated,
        errors_count,
        timestamp
    ) VALUES (
        'comments',
        v_batch_size,
        v_processing_time_ms,
        v_embeddings_generated,
        v_errors_count,
        v_end_time
    );
    
    -- Log success
    ECHO SELECT CONCAT('Processed ', v_batch_size, ' comments in ', 
                       v_processing_time_ms, 'ms') AS result;
                       
EXCEPTION
    WHEN OTHERS THEN
        SET v_errors_count = v_errors_count + 1;
        ECHO SELECT CONCAT('Error processing comments batch: ', @@error_message) AS error;
END;

-- ============================================================================
-- Procedure: update_story_embeddings
-- ============================================================================
-- Updates embeddings for stories that don't have them yet
-- Useful for backfilling or reprocessing
-- Can be called manually or scheduled
--
-- Parameters:
--   limit_count: Maximum number of stories to process (default 100)
-- ============================================================================

CREATE OR REPLACE PROCEDURE update_story_embeddings(limit_count INT)
AS
DECLARE
    v_count INT DEFAULT 0;
BEGIN
    -- Set default if not provided
    IF limit_count IS NULL OR limit_count <= 0 THEN
        SET limit_count = 100;
    END IF;
    
    -- Update stories missing embeddings
    UPDATE hn_stories
    SET 
        title_embedding = cluster.EMBED_TEXT(title),
        combined_embedding = CASE 
            WHEN text IS NOT NULL AND LENGTH(TRIM(text)) > 0 
            THEN cluster.EMBED_TEXT(CONCAT(title, ' ', text))
            ELSE cluster.EMBED_TEXT(title)
        END,
        updated_at = NOW()
    WHERE title_embedding IS NULL
      AND title IS NOT NULL
      AND LENGTH(TRIM(title)) > 0
    LIMIT limit_count;
    
    SET v_count = ROW_COUNT();
    
    ECHO SELECT CONCAT('Updated embeddings for ', v_count, ' stories') AS result;
END;

-- ============================================================================
-- Procedure: update_comment_embeddings
-- ============================================================================
-- Updates embeddings for comments that don't have them yet
-- ============================================================================

CREATE OR REPLACE PROCEDURE update_comment_embeddings(limit_count INT)
AS
DECLARE
    v_count INT DEFAULT 0;
BEGIN
    IF limit_count IS NULL OR limit_count <= 0 THEN
        SET limit_count = 100;
    END IF;
    
    UPDATE hn_comments
    SET 
        text_embedding = cluster.EMBED_TEXT(text),
        updated_at = NOW()
    WHERE text_embedding IS NULL
      AND text IS NOT NULL
      AND LENGTH(TRIM(text)) > 0
      AND LENGTH(text) < 8000
    LIMIT limit_count;
    
    SET v_count = ROW_COUNT();
    
    ECHO SELECT CONCAT('Updated embeddings for ', v_count, ' comments') AS result;
END;

-- ============================================================================
-- Procedure: semantic_search_stories
-- ============================================================================
-- Performs semantic search on stories using EMBED_TEXT()
-- Caches query embeddings for performance
--
-- Parameters:
--   query_text: Natural language search query
--   result_limit: Number of results to return (default 10)
--   min_score: Minimum story score filter (default 0)
-- ============================================================================

CREATE OR REPLACE PROCEDURE semantic_search_stories(
    query_text TEXT,
    result_limit INT,
    min_score INT
)
AS
DECLARE
    v_query_embedding VECTOR(1536);
    v_cached INT DEFAULT 0;
BEGIN
    -- Set defaults
    IF result_limit IS NULL OR result_limit <= 0 THEN
        SET result_limit = 10;
    END IF;
    
    IF min_score IS NULL THEN
        SET min_score = 0;
    END IF;
    
    -- Check cache for this query
    SELECT query_embedding INTO v_query_embedding
    FROM search_cache
    WHERE query_text = query_text
    LIMIT 1;
    
    -- If not in cache, generate and cache it
    IF v_query_embedding IS NULL THEN
        SET v_query_embedding = cluster.EMBED_TEXT(query_text);
        
        INSERT INTO search_cache (query_text, query_embedding, hit_count)
        VALUES (query_text, v_query_embedding, 1)
        ON DUPLICATE KEY UPDATE 
            hit_count = hit_count + 1,
            last_used = NOW();
    ELSE
        -- Update cache hit count
        UPDATE search_cache 
        SET hit_count = hit_count + 1, last_used = NOW()
        WHERE query_text = query_text;
        
        SET v_cached = 1;
    END IF;
    
    -- Perform semantic search using DOT_PRODUCT
    ECHO SELECT 
        s.id,
        s.title,
        s.url,
        s.score,
        s`.by`,
        s.descendants,
        s.time,
        DOT_PRODUCT(s.title_embedding, v_query_embedding) AS similarity,
        v_cached AS from_cache
    FROM hn_stories s
    WHERE s.title_embedding IS NOT NULL
      AND s.score >= min_score
    ORDER BY similarity DESC
    LIMIT result_limit;
END;

-- ============================================================================
-- Procedure: semantic_search_comments
-- ============================================================================
-- Performs semantic search on comments with story context
-- ============================================================================

CREATE OR REPLACE PROCEDURE semantic_search_comments(
    query_text TEXT,
    result_limit INT
)
AS
DECLARE
    v_query_embedding VECTOR(1536);
BEGIN
    IF result_limit IS NULL OR result_limit <= 0 THEN
        SET result_limit = 10;
    END IF;
    
    -- Generate query embedding
    SET v_query_embedding = cluster.EMBED_TEXT(query_text);
    
    -- Search comments with story context
    ECHO SELECT 
        c.id AS comment_id,
        c.text AS comment_text,
        c.by AS comment_author,
        s.id AS story_id,
        s.title AS story_title,
        s.score AS story_score,
        DOT_PRODUCT(c.text_embedding, v_query_embedding) AS similarity
    FROM hn_comments c
    JOIN hn_stories s ON c.story_id = s.id
    WHERE c.text_embedding IS NOT NULL
    ORDER BY similarity DESC
    LIMIT result_limit;
END;

-- ============================================================================
-- Procedure: get_ingestion_stats
-- ============================================================================
-- Returns ingestion statistics for monitoring dashboard
-- ============================================================================

CREATE OR REPLACE PROCEDURE get_ingestion_stats()
AS
BEGIN
    -- Overall counts
    ECHO SELECT 
        (SELECT COUNT(*) FROM hn_stories) AS total_stories,
        (SELECT COUNT(*) FROM hn_comments) AS total_comments,
        (SELECT COUNT(*) FROM hn_stories WHERE title_embedding IS NOT NULL) AS stories_with_embeddings,
        (SELECT COUNT(*) FROM hn_comments WHERE text_embedding IS NOT NULL) AS comments_with_embeddings,
        (SELECT AVG(processing_time_ms) FROM ingestion_stats WHERE stat_type = 'stories' AND timestamp >= NOW() - INTERVAL 1 HOUR) AS avg_story_processing_ms,
        (SELECT AVG(processing_time_ms) FROM ingestion_stats WHERE stat_type = 'comments' AND timestamp >= NOW() - INTERVAL 1 HOUR) AS avg_comment_processing_ms;
    
    -- Recent activity (last hour)
    ECHO SELECT 
        DATE_FORMAT(timestamp, '%Y-%m-%d %H:%i:00') AS minute,
        stat_type,
        SUM(batch_size) AS items_ingested,
        SUM(embeddings_generated) AS embeddings_created
    FROM ingestion_stats
    WHERE timestamp >= NOW() - INTERVAL 1 HOUR
    GROUP BY minute, stat_type
    ORDER BY minute DESC;
END;


-- ============================================================================
-- Procedures created successfully!
-- Next steps:
--   1. Run 03_pipelines.sql to create Kafka pipelines
--   2. These pipelines will call process_stories_batch and process_comments_batch
--   3. Start the data fetcher to begin ingestion
-- ============================================================================

SELECT 'Stored procedures created successfully!' AS status;
SHOW PROCEDURES WHERE Db = 'hackernews_semantic';
