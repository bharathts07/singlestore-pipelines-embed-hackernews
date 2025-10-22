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
            WHEN p_text IS NOT NULL AND LENGTH(TRIM(p_text)) > 0 
            THEN cluster.EMBED_TEXT(p_text)
            ELSE NULL
        END,
        NOW();
END;

-- Semantic search on stories
CREATE OR REPLACE PROCEDURE semantic_search_stories(
    query_text TEXT,
    result_limit INT,
    min_score INT
) AS
DECLARE
    v_query_embedding VECTOR(2048);
    v_cached INT DEFAULT 0;
BEGIN
    IF result_limit IS NULL OR result_limit <= 0 THEN
        SET result_limit = 10;
    END IF;
    IF min_score IS NULL THEN
        SET min_score = 0;
    END IF;
    
    SELECT query_embedding INTO v_query_embedding
    FROM search_cache WHERE query_text = query_text LIMIT 1;
    
    IF v_query_embedding IS NULL THEN
        SET v_query_embedding = cluster.EMBED_TEXT(query_text);
        INSERT IGNORE INTO search_cache (query_text, query_embedding, created_at)
        VALUES (query_text, v_query_embedding, NOW());
    ELSE
        SET v_cached = 1;
    END IF;
    
    ECHO SELECT 
        s.id, s.title, s.url, s.score, s.`by`, s.descendants, s.time,
        DOT_PRODUCT(s.title_embedding, v_query_embedding) AS similarity,
        v_cached AS from_cache
    FROM hn_stories s
    WHERE s.title_embedding IS NOT NULL AND s.score >= min_score
    ORDER BY similarity DESC
    LIMIT result_limit;
END;

-- Semantic search on comments
CREATE OR REPLACE PROCEDURE semantic_search_comments(
    query_text TEXT,
    result_limit INT
) AS
DECLARE
    v_query_embedding VECTOR(2048);
BEGIN
    IF result_limit IS NULL OR result_limit <= 0 THEN
        SET result_limit = 10;
    END IF;
    
    SET v_query_embedding = cluster.EMBED_TEXT(query_text);
    
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

-- Get ingestion statistics
CREATE OR REPLACE PROCEDURE get_ingestion_stats() AS
BEGIN
    ECHO SELECT 
        (SELECT COUNT(*) FROM hn_stories) AS total_stories,
        (SELECT COUNT(*) FROM hn_comments) AS total_comments,
        (SELECT COUNT(*) FROM hn_stories WHERE title_embedding IS NOT NULL) AS stories_with_embeddings,
        (SELECT COUNT(*) FROM hn_comments WHERE text_embedding IS NOT NULL) AS comments_with_embeddings;
END;
