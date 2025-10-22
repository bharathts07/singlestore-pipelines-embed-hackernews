-- Stored procedures for direct ingestion with EMBED_TEXT
USE hackernews_semantic;

-- Insert single story with embeddings
CREATE OR REPLACE PROCEDURE insert_story(
    p_id BIGINT,
    p_title TEXT,
    p_url TEXT,
    p_score INT,
    p_by VARCHAR(255),
    p_time BIGINT,
    p_descendants INT,
    p_type VARCHAR(50),
    p_text TEXT
) AS
BEGIN
    INSERT IGNORE INTO hn_stories (
        id, title, url, score, `by`, time, descendants, type, text,
        title_embedding, combined_embedding, created_at
    )
    SELECT
        p_id, p_title, p_url, COALESCE(p_score, 0), p_by,
        FROM_UNIXTIME(p_time), COALESCE(p_descendants, 0), p_type, p_text,
        cluster.EMBED_TEXT(p_title),
        CASE 
            WHEN p_text IS NOT NULL AND LENGTH(TRIM(p_text)) > 0 
            THEN cluster.EMBED_TEXT(CONCAT(p_title, ' ', p_text))
            ELSE cluster.EMBED_TEXT(p_title)
        END,
        NOW();
END;

-- Insert single comment with embeddings
CREATE OR REPLACE PROCEDURE insert_comment(
    p_id BIGINT,
    p_parent_id BIGINT,
    p_story_id BIGINT,
    p_by VARCHAR(255),
    p_time BIGINT,
    p_type VARCHAR(50),
    p_text TEXT
) AS
BEGIN
    INSERT IGNORE INTO hn_comments (
        id, parent_id, story_id, `by`, time, type, text,
        text_embedding, created_at
    )
    SELECT
        p_id, p_parent_id, p_story_id, p_by,
        FROM_UNIXTIME(p_time), p_type, p_text,
        CASE 
            WHEN p_text IS NOT NULL AND CHAR_LENGTH(TRIM(REPLACE(REPLACE(p_text, '\n', ''), '\r', ''))) >= 1
            THEN cluster.EMBED_TEXT(TRIM(p_text))
            ELSE NULL
        END,
        NOW();
END;

-- Semantic search on stories using native SingleStore DOT_PRODUCT
CREATE OR REPLACE PROCEDURE semantic_search_stories(
    p_query_text TEXT,
    p_result_limit INT,
    p_min_score INT
) AS
BEGIN
    IF p_result_limit IS NULL OR p_result_limit <= 0 THEN
        SET p_result_limit = 10;
    END IF;
    
    IF p_min_score IS NULL THEN
        SET p_min_score = 0;
    END IF;
    
    ECHO SELECT 
        s.id, s.title, s.url, s.score, s.`by`, s.descendants, s.time,
        DOT_PRODUCT(s.title_embedding, cluster.EMBED_TEXT(p_query_text):>VECTOR(2048)) AS similarity
    FROM hn_stories s
    WHERE s.title_embedding IS NOT NULL AND s.score >= p_min_score
    ORDER BY similarity DESC
    LIMIT p_result_limit;
END;

-- Semantic search on comments
CREATE OR REPLACE PROCEDURE semantic_search_comments(
    p_query_text TEXT,
    p_result_limit INT
) AS
BEGIN
    IF p_result_limit IS NULL OR p_result_limit <= 0 THEN
        SET p_result_limit = 10;
    END IF;
    
    ECHO SELECT 
        c.id AS comment_id,
        c.text AS comment_text,
        c.by AS comment_author,
        s.id AS story_id,
        s.title AS story_title,
        s.score AS story_score,
        DOT_PRODUCT(c.text_embedding, cluster.EMBED_TEXT(p_query_text):>VECTOR(2048)) AS similarity
    FROM hn_comments c
    JOIN hn_stories s ON c.story_id = s.id
    WHERE c.text_embedding IS NOT NULL
    ORDER BY similarity DESC
    LIMIT p_result_limit;
END;

-- Get ingestion statistics
CREATE OR REPLACE PROCEDURE get_ingestion_stats() AS
BEGIN
    ECHO SELECT 
        (SELECT COUNT(*) FROM hn_stories) AS total_stories,
        (SELECT COUNT(*) FROM hn_comments) AS total_comments,
        (SELECT COUNT(*) FROM hn_stories WHERE title_embedding IS NOT NULL) AS stories_with_embeddings,
        (SELECT COUNT(*) FROM hn_comments WHERE text_embedding IS NOT NULL) AS comments_with_embeddings;
END;
