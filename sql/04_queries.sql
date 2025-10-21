-- ============================================================================
-- Example Semantic Search Queries for Hacker News Demo
-- ============================================================================
-- This file contains example queries demonstrating the power of semantic
-- search with EMBED_TEXT() and vector similarity
--
-- All queries use the DOT_PRODUCT function for cosine similarity
-- (assumes vectors are normalized, which they are with most embedding models)
-- ============================================================================

USE hackernews_semantic;

-- ============================================================================
-- 1. BASIC SEMANTIC SEARCH
-- ============================================================================

-- Example 1: Search for database performance content
-- This will match: "query optimization", "indexing strategies", "SQL tuning"
-- even though those exact words aren't in the query

SET @query = 'database performance optimization';
SET @query_embedding = cluster.EMBED_TEXT(@query);

SELECT 
    id,
    title,
    url,
    score,
    by AS author,
    time AS posted_time,
    DOT_PRODUCT(title_embedding, @query_embedding) AS similarity_score
FROM hn_stories
WHERE title_embedding IS NOT NULL
ORDER BY similarity_score DESC
LIMIT 10;

-- ============================================================================

-- Example 2: Search for machine learning infrastructure
-- Will find: "ML ops", "model deployment", "training at scale", etc.

SET @query = 'machine learning infrastructure and deployment';
SET @query_embedding = cluster.EMBED_TEXT(@query);

SELECT 
    id,
    title,
    score,
    descendants AS comment_count,
    DOT_PRODUCT(title_embedding, @query_embedding) AS similarity_score
FROM hn_stories
WHERE title_embedding IS NOT NULL
ORDER BY similarity_score DESC
LIMIT 10;

-- ============================================================================

-- Example 3: Startup funding and investment
-- Will find: "Series A", "venture capital", "angel investors", "fundraising"

SET @query = 'startup funding and investment strategies';
SET @query_embedding = cluster.EMBED_TEXT(@query);

SELECT 
    id,
    title,
    url,
    score,
    DOT_PRODUCT(title_embedding, @query_embedding) AS similarity_score
FROM hn_stories
WHERE title_embedding IS NOT NULL
  AND score > 10  -- Filter for quality content
ORDER BY similarity_score DESC
LIMIT 10;

-- ============================================================================
-- 2. SEMANTIC SEARCH ON COMMENTS
-- ============================================================================

-- Example 4: Find comments discussing specific topics with story context

SET @query = 'distributed systems and scalability challenges';
SET @query_embedding = cluster.EMBED_TEXT(@query);

SELECT 
    c.id AS comment_id,
    LEFT(c.text, 200) AS comment_preview,
    c.by AS comment_author,
    s.id AS story_id,
    s.title AS story_title,
    s.score AS story_score,
    DOT_PRODUCT(c.text_embedding, @query_embedding) AS similarity_score
FROM hn_comments c
JOIN hn_stories s ON c.story_id = s.id
WHERE c.text_embedding IS NOT NULL
ORDER BY similarity_score DESC
LIMIT 10;

-- ============================================================================
-- 3. HYBRID SEARCH (Semantic + Metadata Filtering)
-- ============================================================================

-- Example 5: Popular stories about AI/ML from the last 7 days

SET @query = 'artificial intelligence and large language models';
SET @query_embedding = cluster.EMBED_TEXT(@query);

SELECT 
    id,
    title,
    url,
    score,
    by AS author,
    time AS posted_time,
    descendants AS comments,
    DOT_PRODUCT(title_embedding, @query_embedding) AS similarity_score
FROM hn_stories
WHERE title_embedding IS NOT NULL
  AND time >= NOW() - INTERVAL 7 DAY
  AND score > 50
ORDER BY similarity_score DESC, score DESC
LIMIT 20;

-- ============================================================================

-- Example 6: Search with category filtering (Ask HN, Show HN, etc.)

SET @query = 'career advice and job hunting tips';
SET @query_embedding = cluster.EMBED_TEXT(@query);

SELECT 
    id,
    title,
    type,
    score,
    DOT_PRODUCT(title_embedding, @query_embedding) AS similarity_score
FROM hn_stories
WHERE title_embedding IS NOT NULL
  AND type IN ('ask', 'story')
ORDER BY similarity_score DESC
LIMIT 15;

-- ============================================================================
-- 4. COMPARING SEMANTIC VS KEYWORD SEARCH
-- ============================================================================

-- Example 7: Side-by-side comparison
-- Query: "remote work"
-- Semantic will find: "distributed teams", "work from home", "WFH", etc.
-- Keyword will only find exact "remote work"

-- Semantic search
SET @query = 'remote work and distributed teams';
SET @query_embedding = cluster.EMBED_TEXT(@query);

SELECT 
    'SEMANTIC' AS search_type,
    id,
    title,
    score,
    DOT_PRODUCT(title_embedding, @query_embedding) AS similarity_score
FROM hn_stories
WHERE title_embedding IS NOT NULL
ORDER BY similarity_score DESC
LIMIT 5;

-- Keyword search (for comparison)
SELECT 
    'KEYWORD' AS search_type,
    id,
    title,
    score,
    NULL AS similarity_score
FROM hn_stories
WHERE title LIKE '%remote work%'
   OR title LIKE '%remote%'
ORDER BY score DESC
LIMIT 5;

-- ============================================================================
-- 5. SEMANTIC AGGREGATIONS AND ANALYTICS
-- ============================================================================

-- Example 8: Find top authors writing about a topic

SET @query = 'web development frameworks';
SET @query_embedding = cluster.EMBED_TEXT(@query);

SELECT 
    by AS author,
    COUNT(*) AS relevant_stories,
    AVG(score) AS avg_score,
    AVG(DOT_PRODUCT(title_embedding, @query_embedding)) AS avg_similarity
FROM hn_stories
WHERE title_embedding IS NOT NULL
  AND by IS NOT NULL
  AND DOT_PRODUCT(title_embedding, @query_embedding) > 0.7
GROUP BY by
HAVING relevant_stories >= 2
ORDER BY avg_similarity DESC, relevant_stories DESC
LIMIT 10;

-- ============================================================================

-- Example 9: Trending topics over time (semantic time series)

SET @query = 'cryptocurrency and blockchain';
SET @query_embedding = cluster.EMBED_TEXT(@query);

SELECT 
    DATE_FORMAT(time, '%Y-%m-%d') AS date,
    COUNT(*) AS relevant_stories,
    AVG(score) AS avg_score,
    MAX(DOT_PRODUCT(title_embedding, @query_embedding)) AS max_similarity
FROM hn_stories
WHERE title_embedding IS NOT NULL
  AND time >= NOW() - INTERVAL 30 DAY
  AND DOT_PRODUCT(title_embedding, @query_embedding) > 0.6
GROUP BY date
ORDER BY date DESC;

-- ============================================================================
-- 6. ADVANCED: MULTI-VECTOR SEARCH
-- ============================================================================

-- Example 10: Search using both title and combined embeddings
-- Combined embeddings include the story text, providing more context

SET @query = 'software engineering best practices';
SET @query_embedding = cluster.EMBED_TEXT(@query);

SELECT 
    id,
    title,
    score,
    descendants,
    DOT_PRODUCT(title_embedding, @query_embedding) AS title_similarity,
    DOT_PRODUCT(combined_embedding, @query_embedding) AS combined_similarity,
    -- Weighted average: title more important than body
    (DOT_PRODUCT(title_embedding, @query_embedding) * 0.7 + 
     DOT_PRODUCT(combined_embedding, @query_embedding) * 0.3) AS weighted_similarity
FROM hn_stories
WHERE title_embedding IS NOT NULL
  AND combined_embedding IS NOT NULL
ORDER BY weighted_similarity DESC
LIMIT 10;

-- ============================================================================
-- 7. SEMANTIC CLUSTERING / SIMILAR STORIES
-- ============================================================================

-- Example 11: Find stories similar to a specific story
-- Replace {STORY_ID} with actual story ID

SET @story_id = 12345;  -- Replace with actual story ID

SELECT 
    s2.id,
    s2.title,
    s2.score,
    DOT_PRODUCT(s1.title_embedding, s2.title_embedding) AS similarity
FROM hn_stories s1
CROSS JOIN hn_stories s2
WHERE s1.id = @story_id
  AND s2.id != @story_id
  AND s1.title_embedding IS NOT NULL
  AND s2.title_embedding IS NOT NULL
ORDER BY similarity DESC
LIMIT 10;

-- ============================================================================
-- 8. USING STORED PROCEDURES FOR SEMANTIC SEARCH
-- ============================================================================

-- Example 12: Use the semantic search stored procedure with caching

CALL semantic_search_stories(
    'kubernetes and container orchestration',
    10,  -- limit
    10   -- min_score
);

-- ============================================================================

-- Example 13: Search comments with story context

CALL semantic_search_comments(
    'testing strategies and QA automation',
    15  -- limit
);

-- ============================================================================
-- 9. MONITORING AND STATISTICS
-- ============================================================================

-- Example 14: Get overall ingestion statistics

CALL get_ingestion_stats();

-- ============================================================================

-- Example 15: Check embedding coverage

SELECT 
    'Stories' AS item_type,
    COUNT(*) AS total,
    SUM(CASE WHEN title_embedding IS NOT NULL THEN 1 ELSE 0 END) AS with_embeddings,
    ROUND(SUM(CASE WHEN title_embedding IS NOT NULL THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS coverage_percent
FROM hn_stories
UNION ALL
SELECT 
    'Comments' AS item_type,
    COUNT(*) AS total,
    SUM(CASE WHEN text_embedding IS NOT NULL THEN 1 ELSE 0 END) AS with_embeddings,
    ROUND(SUM(CASE WHEN text_embedding IS NOT NULL THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS coverage_percent
FROM hn_comments;

-- ============================================================================

-- Example 16: Recent ingestion activity

SELECT * FROM v_recent_activity LIMIT 20;

-- ============================================================================

-- Example 17: Top stories by score

SELECT * FROM v_top_stories LIMIT 20;

-- ============================================================================

-- Example 18: Pipeline health check

SELECT 
    pipeline_name,
    state,
    batches_success,
    batches_error,
    rows_success,
    rows_error,
    ROUND(rows_success / (batches_success + 0.001), 2) AS avg_rows_per_batch,
    ROUND(rows_error * 100.0 / (rows_success + rows_error + 0.001), 2) AS error_rate_percent
FROM information_schema.PIPELINES
WHERE database_name = 'hackernews_semantic';

-- ============================================================================
-- 10. DEMO QUERIES FOR PRESENTATION
-- ============================================================================

-- Demo Query 1: Show the difference between keyword and semantic search

-- Keyword search for "database"
SELECT 'KEYWORD: database' AS search_method, title, score
FROM hn_stories
WHERE title LIKE '%database%'
ORDER BY score DESC
LIMIT 5;

-- Semantic search for "database"
SET @query_embedding = cluster.EMBED_TEXT('database');
SELECT 'SEMANTIC: database' AS search_method, 
       title, 
       score,
       DOT_PRODUCT(title_embedding, @query_embedding) AS similarity
FROM hn_stories
WHERE title_embedding IS NOT NULL
ORDER BY similarity DESC
LIMIT 5;

-- ============================================================================

-- Demo Query 2: Real-time semantic search showcase

SET @demo_query = 'innovative startup ideas and entrepreneurship';
SET @demo_embedding = cluster.EMBED_TEXT(@demo_query);

SELECT 
    title,
    url,
    score,
    ROUND(DOT_PRODUCT(title_embedding, @demo_embedding), 3) AS similarity,
    time AS posted_at
FROM hn_stories
WHERE title_embedding IS NOT NULL
ORDER BY similarity DESC
LIMIT 10;

-- ============================================================================

-- Demo Query 3: Show real-time ingestion

SELECT 
    COUNT(*) AS stories_last_5_min,
    MAX(created_at) AS most_recent
FROM hn_stories
WHERE created_at >= NOW() - INTERVAL 5 MINUTE;

SELECT 
    COUNT(*) AS comments_last_5_min,
    MAX(created_at) AS most_recent
FROM hn_comments
WHERE created_at >= NOW() - INTERVAL 5 MINUTE;

-- ============================================================================
-- Tips for Demo:
-- ============================================================================
-- 1. Start with basic semantic search to show functionality
-- 2. Compare with keyword search to highlight semantic understanding
-- 3. Show hybrid search combining semantic + metadata
-- 4. Demonstrate real-time ingestion with monitoring queries
-- 5. Use stored procedures to show caching and performance
-- 6. Highlight the pipeline efficiency (no triggers needed!)
-- ============================================================================

SELECT 'Example queries ready to use!' AS status;
SELECT 'Modify @query variables with your own search terms' AS tip;
