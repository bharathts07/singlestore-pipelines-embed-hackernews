"""
SingleStore Semantic Search Dashboard
=====================================

FastAPI backend for the Hacker News semantic search demo dashboard.

Provides endpoints for:
- Semantic search on stories and comments
- Real-time ingestion statistics
- Pipeline monitoring
- Demo queries

Author: SingleStore Demo
"""

from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import HTMLResponse
from pydantic import BaseModel
from typing import List, Optional
import os
import singlestoredb as s2
from dotenv import load_dotenv
import logging

# Load environment variables
load_dotenv()

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize FastAPI app
app = FastAPI(
    title="SingleStore Semantic Search Dashboard",
    description="Real-time semantic search on Hacker News using SingleStore Pipelines + EMBED_TEXT()",
    version="1.0.0"
)

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# SingleStore connection configuration
S2_CONFIG = {
    "host": os.getenv("SINGLESTORE_HOST"),
    "port": int(os.getenv("SINGLESTORE_PORT", 3306)),
    "user": os.getenv("SINGLESTORE_USER"),
    "password": os.getenv("SINGLESTORE_PASSWORD"),
    "database": os.getenv("SINGLESTORE_DATABASE", "hackernews_semantic")
}

# ============================================================================
# Data Models
# ============================================================================

class SearchQuery(BaseModel):
    query: str
    limit: int = 10
    min_score: int = 0

class StoryResult(BaseModel):
    id: int
    title: str
    url: Optional[str]
    score: int
    by: str
    descendants: int
    time: str
    similarity: float

class CommentResult(BaseModel):
    comment_id: int
    comment_text: str
    comment_author: str
    story_id: int
    story_title: str
    story_score: int
    similarity: float

class Stats(BaseModel):
    total_stories: int
    total_comments: int
    stories_with_embeddings: int
    comments_with_embeddings: int
    avg_story_processing_ms: Optional[float]
    avg_comment_processing_ms: Optional[float]

# ============================================================================
# Database Utilities
# ============================================================================

def get_connection():
    """Get SingleStore database connection"""
    try:
        conn = s2.connect(**S2_CONFIG)
        return conn
    except Exception as e:
        logger.error(f"Database connection error: {e}")
        raise HTTPException(status_code=500, detail="Database connection failed")

# ============================================================================
# API Endpoints
# ============================================================================

@app.get("/", response_class=HTMLResponse)
async def root():
    """Serve the main dashboard HTML"""
    try:
        with open("static/index.html", "r") as f:
            return f.read()
    except FileNotFoundError:
        return """
        <html>
            <head><title>SingleStore Semantic Search</title></head>
            <body>
                <h1>Dashboard Starting...</h1>
                <p>Please ensure static files are available.</p>
            </body>
        </html>
        """

@app.get("/api/health")
async def health_check():
    """Health check endpoint"""
    try:
        conn = get_connection()
        conn.close()
        return {"status": "healthy", "database": "connected"}
    except Exception as e:
        return {"status": "unhealthy", "error": str(e)}

@app.post("/api/search/stories", response_model=List[StoryResult])
async def search_stories(search: SearchQuery):
    """
    Semantic search on stories
    """
    conn = get_connection()
    try:
        with conn.cursor() as cursor:
            # Generate embedding for the query
            cursor.execute(
                "SELECT cluster.EMBED_TEXT(%s) AS embedding",
                (search.query,)
            )
            query_embedding = cursor.fetchone()[0]
            
            # Perform semantic search
            cursor.execute("""
                SELECT 
                    id,
                    title,
                    url,
                    score,
                    `by` AS author,
                    descendants,
                    DATE_FORMAT(time, '%%Y-%%m-%%d %%H:%%i:%%s') AS time,
                    DOT_PRODUCT(title_embedding, %s) AS similarity
                FROM hn_stories
                WHERE title_embedding IS NOT NULL
                  AND score >= %s
                ORDER BY similarity DESC
                LIMIT %s
            """, (query_embedding, search.min_score, search.limit))
            
            results = []
            for row in cursor.fetchall():
                results.append(StoryResult(
                    id=row[0],
                    title=row[1],
                    url=row[2],
                    score=row[3],
                    by=row[4],
                    descendants=row[5],
                    time=row[6],
                    similarity=float(row[7])
                ))
            
            return results
    finally:
        conn.close()

@app.post("/api/search/comments", response_model=List[CommentResult])
async def search_comments(search: SearchQuery):
    """
    Semantic search on comments
    """
    conn = get_connection()
    try:
        with conn.cursor() as cursor:
            # Generate embedding for the query
            cursor.execute(
                "SELECT cluster.EMBED_TEXT(%s) AS embedding",
                (search.query,)
            )
            query_embedding = cursor.fetchone()[0]
            
            # Perform semantic search
            cursor.execute("""
                SELECT 
                    c.id AS comment_id,
                    c.text AS comment_text,
                    c.`by` AS comment_author,
                    s.id AS story_id,
                    s.title AS story_title,
                    s.score AS story_score,
                    DOT_PRODUCT(c.text_embedding, %s) AS similarity
                FROM hn_comments c
                JOIN hn_stories s ON c.story_id = s.id
                WHERE c.text_embedding IS NOT NULL
                ORDER BY similarity DESC
                LIMIT %s
            """, (query_embedding, search.limit))
            
            results = []
            for row in cursor.fetchall():
                results.append(CommentResult(
                    comment_id=row[0],
                    comment_text=row[1][:200],  # Truncate long comments
                    comment_author=row[2],
                    story_id=row[3],
                    story_title=row[4],
                    story_score=row[5],
                    similarity=float(row[6])
                ))
            
            return results
    finally:
        conn.close()

@app.get("/api/stats", response_model=Stats)
async def get_stats():
    """
    Get overall ingestion statistics
    """
    conn = get_connection()
    try:
        with conn.cursor() as cursor:
            cursor.execute("""
                SELECT 
                    (SELECT COUNT(*) FROM hn_stories) AS total_stories,
                    (SELECT COUNT(*) FROM hn_comments) AS total_comments,
                    (SELECT COUNT(*) FROM hn_stories WHERE title_embedding IS NOT NULL) AS stories_with_embeddings,
                    (SELECT COUNT(*) FROM hn_comments WHERE text_embedding IS NOT NULL) AS comments_with_embeddings,
                    (SELECT AVG(processing_time_ms) FROM ingestion_stats 
                     WHERE stat_type = 'stories' AND timestamp >= NOW() - INTERVAL 1 HOUR) AS avg_story_processing_ms,
                    (SELECT AVG(processing_time_ms) FROM ingestion_stats 
                     WHERE stat_type = 'comments' AND timestamp >= NOW() - INTERVAL 1 HOUR) AS avg_comment_processing_ms
            """)
            
            row = cursor.fetchone()
            return Stats(
                total_stories=row[0],
                total_comments=row[1],
                stories_with_embeddings=row[2],
                comments_with_embeddings=row[3],
                avg_story_processing_ms=float(row[4]) if row[4] else None,
                avg_comment_processing_ms=float(row[5]) if row[5] else None
            )
    finally:
        conn.close()

@app.get("/api/recent-stories")
async def get_recent_stories(limit: int = Query(default=20, le=100)):
    """
    Get most recently ingested stories
    """
    conn = get_connection()
    try:
        with conn.cursor() as cursor:
            cursor.execute("""
                SELECT 
                    id,
                    title,
                    score,
                    `by` AS author,
                    DATE_FORMAT(created_at, '%%Y-%%m-%%d %%H:%%i:%%s') AS ingested_at
                FROM hn_stories
                ORDER BY created_at DESC
                LIMIT %s
            """, (limit,))
            
            results = []
            for row in cursor.fetchall():
                results.append({
                    "id": row[0],
                    "title": row[1],
                    "score": row[2],
                    "author": row[3],
                    "ingested_at": row[4]
                })
            
            return results
    finally:
        conn.close()

@app.get("/api/ingestion-rate")
async def get_ingestion_rate():
    """
    Get ingestion rate for the last hour
    """
    conn = get_connection()
    try:
        with conn.cursor() as cursor:
            cursor.execute("""
                SELECT 
                    DATE_FORMAT(created_at, '%%Y-%%m-%%d %%H:%%i:00') AS minute,
                    COUNT(*) AS count
                FROM hn_stories
                WHERE created_at >= NOW() - INTERVAL 1 HOUR
                GROUP BY minute
                ORDER BY minute DESC
            """)
            
            results = []
            for row in cursor.fetchall():
                results.append({
                    "minute": row[0],
                    "count": row[1]
                })
            
            return results
    finally:
        conn.close()

@app.get("/api/pipeline-status")
async def get_pipeline_status():
    """
    Get pipeline status and metrics
    """
    conn = get_connection()
    try:
        with conn.cursor() as cursor:
            cursor.execute("""
                SELECT 
                    pipeline_name,
                    state,
                    batches_success,
                    batches_error,
                    rows_success,
                    rows_error
                FROM information_schema.PIPELINES
                WHERE database_name = %s
                ORDER BY pipeline_name
            """, (S2_CONFIG["database"],))
            
            results = []
            for row in cursor.fetchall():
                results.append({
                    "pipeline_name": row[0],
                    "state": row[1],
                    "batches_success": row[2],
                    "batches_error": row[3],
                    "rows_success": row[4],
                    "rows_error": row[5]
                })
            
            return results
    finally:
        conn.close()

# ============================================================================
# Main entry point
# ============================================================================

if __name__ == "__main__":
    import uvicorn
    
    host = os.getenv("DASHBOARD_HOST", "0.0.0.0")
    port = int(os.getenv("DASHBOARD_PORT", 5000))
    
    logger.info(f"Starting dashboard on {host}:{port}")
    logger.info(f"Connecting to SingleStore: {S2_CONFIG['host']}")
    
    uvicorn.run(app, host=host, port=port)
