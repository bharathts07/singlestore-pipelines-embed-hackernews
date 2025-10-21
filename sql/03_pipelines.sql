-- ============================================================================
-- SingleStore Pipelines for Hacker News Data Ingestion
-- ============================================================================
-- These pipelines consume data from Kafka topics and process them through
-- stored procedures that generate vector embeddings using EMBED_TEXT()
--
-- Prerequisites:
--   - Schema created (01_schema.sql)
--   - Procedures created (02_procedures.sql)
--   - Kafka running with topics: hn-stories, hn-comments
--   - Environment variables configured in .env
-- ============================================================================

USE hackernews_semantic;

-- ============================================================================
-- Pipeline: hn_stories_pipeline
-- ============================================================================
-- Consumes story data from Kafka topic and processes through stored procedure
-- The procedure calls EMBED_TEXT() to generate vector embeddings
--
-- Configuration:
--   - Source: Kafka topic 'hn-stories'
--   - Format: JSON
--   - Processing: INTO PROCEDURE process_stories_batch
--   - Error handling: SKIP ALL ERRORS (continue on errors)
-- ============================================================================

-- Drop existing pipeline if it exists
DROP PIPELINE IF EXISTS hn_stories_pipeline;

-- Create the stories pipeline
-- CONFIG is replaced by setup script based on environment (PLAINTEXT or SASL_SSL)
CREATE PIPELINE hn_stories_pipeline AS
LOAD DATA KAFKA '${KAFKA_BOOTSTRAP_SERVERS}/${KAFKA_TOPIC_STORIES}'
    CONFIG '${KAFKA_CONFIG}'
    
    -- Batch configuration for optimal performance
    BATCH_INTERVAL 5000  -- Process every 5 seconds
    MAX_PARTITIONS_PER_BATCH 4  -- Process up to 4 partitions in parallel
    
    -- Error handling: skip parser errors (required for procedure pipelines)
    SKIP PARSER ERRORS
    
    -- Process through stored procedure that calls EMBED_TEXT()
    INTO PROCEDURE process_stories_batch
    
    -- JSON format mapping
    FORMAT JSON (
        id <- id,
        title <- title,
        url <- url,
        score <- score,
        `by` <- `by`,
        time <- time,
        descendants <- descendants,
        type <- type,
        text <- text
    );

-- ============================================================================
-- Pipeline: hn_comments_pipeline
-- ============================================================================
-- Consumes comment data from Kafka topic and processes through stored procedure
-- The procedure calls EMBED_TEXT() to generate vector embeddings
-- ============================================================================

-- Drop existing pipeline if it exists
DROP PIPELINE IF EXISTS hn_comments_pipeline;

-- Create the comments pipeline
-- CONFIG is replaced by setup script based on environment (PLAINTEXT or SASL_SSL)
CREATE PIPELINE hn_comments_pipeline AS
LOAD DATA KAFKA '${KAFKA_BOOTSTRAP_SERVERS}/${KAFKA_TOPIC_COMMENTS}'
    CONFIG '${KAFKA_CONFIG}'
    
    -- Batch configuration
    BATCH_INTERVAL 5000
    MAX_PARTITIONS_PER_BATCH 4
    
    -- Error handling: skip parser errors (required for procedure pipelines)
    SKIP PARSER ERRORS
    
    -- Process through stored procedure
    INTO PROCEDURE process_comments_batch
    
    -- JSON format mapping
    FORMAT JSON (
        id <- id,
        parent_id <- parent,
        story_id <- story_id,
        `by` <- `by`,
        time <- time,
        type <- type,
        text <- text
    );

-- ============================================================================
-- Start the pipelines
-- ============================================================================
-- Note: Pipelines will start consuming from Kafka immediately
-- Make sure Kafka is running and topics exist before starting
-- ============================================================================

START PIPELINE hn_stories_pipeline;
START PIPELINE hn_comments_pipeline;

-- ============================================================================
-- Verify pipeline status
-- ============================================================================

SELECT 
    pipeline_name,
    state,
    batches_success,
    batches_error,
    rows_success,
    rows_error
FROM information_schema.PIPELINES
WHERE database_name = 'hackernews_semantic'
ORDER BY pipeline_name;

-- ============================================================================
-- Useful Pipeline Management Commands
-- ============================================================================

-- Stop a pipeline
-- STOP PIPELINE hn_stories_pipeline;
-- STOP PIPELINE hn_comments_pipeline;

-- Start a pipeline
-- START PIPELINE hn_stories_pipeline;
-- START PIPELINE hn_comments_pipeline;

-- Check pipeline errors
-- SELECT * FROM information_schema.PIPELINES_ERRORS
-- WHERE pipeline_name IN ('hn_stories_pipeline', 'hn_comments_pipeline')
-- ORDER BY error_time DESC
-- LIMIT 20;

-- Clear pipeline errors
-- CLEAR PIPELINE ERRORS hn_stories_pipeline;
-- CLEAR PIPELINE ERRORS hn_comments_pipeline;

-- Drop pipelines (if needed)
-- DROP PIPELINE hn_stories_pipeline;
-- DROP PIPELINE hn_comments_pipeline;

-- View pipeline configuration
-- SHOW CREATE PIPELINE hn_stories_pipeline;
-- SHOW CREATE PIPELINE hn_comments_pipeline;

-- Alter pipeline (e.g., change batch interval)
-- ALTER PIPELINE hn_stories_pipeline SET BATCH_INTERVAL = 10000;

-- ============================================================================
-- Pipeline Monitoring Queries
-- ============================================================================

-- Real-time pipeline activity
-- SELECT 
--     pipeline_name,
--     state,
--     rows_success AS total_rows,
--     rows_error AS failed_rows,
--     ROUND(rows_success / (batches_success + 0.001), 2) AS avg_rows_per_batch,
--     batches_success,
--     batches_error
-- FROM information_schema.PIPELINES
-- WHERE database_name = 'hackernews_semantic';

-- Recent pipeline batches
-- SELECT 
--     pipeline_name,
--     batch_id,
--     batch_state,
--     batch_source_partition_id,
--     batch_rows_inserted,
--     batch_create_time,
--     batch_start_time,
--     batch_finish_time
-- FROM information_schema.PIPELINES_BATCHES
-- WHERE database_name = 'hackernews_semantic'
-- ORDER BY batch_create_time DESC
-- LIMIT 20;

-- ============================================================================
-- Troubleshooting
-- ============================================================================

-- If pipelines are not starting:
-- 1. Verify Kafka is running: docker-compose ps
-- 2. Check Kafka topics exist: 
--    docker-compose exec kafka kafka-topics.sh --list --bootstrap-server localhost:9092
-- 3. Verify network connectivity from SingleStore to Kafka
-- 4. Check pipeline errors: SELECT * FROM information_schema.PIPELINES_ERRORS

-- If embeddings are not being generated:
-- 1. Verify AI Functions are installed in your workspace
-- 2. Test EMBED_TEXT() manually: SELECT cluster.EMBED_TEXT('test');
-- 3. Check stored procedure execution: CALL get_ingestion_stats();

-- Performance tuning:
-- 1. Adjust BATCH_INTERVAL (lower = more frequent, higher = larger batches)
-- 2. Adjust MAX_PARTITIONS_PER_BATCH based on your Kafka partition count
-- 3. Monitor ingestion_stats table for processing times
-- 4. Consider using multiple pipelines for high-volume scenarios

-- ============================================================================

SELECT 'Pipelines created and started successfully!' AS status;
SELECT 'Monitor progress in information_schema.PIPELINES' AS next_step;
