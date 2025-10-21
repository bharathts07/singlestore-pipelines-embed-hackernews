#!/usr/bin/env python3
"""
Monitor Script for SingleStore Hacker News Semantic Search Demo

This script provides real-time monitoring of the demo system including:
- Pipeline status and health
- Ingestion statistics
- Data counts
- Recent activity
"""

import os
import sys
import time
import singlestoredb as s2
from dotenv import load_dotenv
from datetime import datetime

# Load environment variables
load_dotenv()

# SingleStore connection configuration
S2_CONFIG = {
    "host": os.getenv("SINGLESTORE_HOST"),
    "port": int(os.getenv("SINGLESTORE_PORT", 3306)),
    "user": os.getenv("SINGLESTORE_USER"),
    "password": os.getenv("SINGLESTORE_PASSWORD"),
    "database": os.getenv("SINGLESTORE_DATABASE", "hn_semantic_search")
}


def clear_screen():
    """Clear the terminal screen"""
    os.system('clear' if os.name != 'nt' else 'cls')


def get_pipeline_status(conn):
    """Get pipeline status"""
    with conn.cursor() as cursor:
        cursor.execute("""
            SELECT 
                PIPELINE_NAME,
                STATE,
                BATCH_STATE,
                BATCH_INTERVAL_MS,
                BATCH_COUNT,
                ROWS_PARSED,
                ROWS_WRITTEN,
                LAST_ERROR
            FROM information_schema.PIPELINES
            WHERE DATABASE_NAME = %s
        """, (S2_CONFIG["database"],))
        return cursor.fetchall()


def get_stats(conn):
    """Get ingestion statistics"""
    with conn.cursor() as cursor:
        cursor.execute("CALL get_ingestion_stats()")
        return cursor.fetchall()


def get_counts(conn):
    """Get table row counts"""
    with conn.cursor() as cursor:
        cursor.execute("SELECT COUNT(*) FROM hn_stories")
        stories = cursor.fetchone()[0]
        
        cursor.execute("SELECT COUNT(*) FROM hn_comments")
        comments = cursor.fetchone()[0]
        
        cursor.execute("SELECT COUNT(*) FROM hn_stories WHERE title_embedding IS NOT NULL")
        embedded_stories = cursor.fetchone()[0]
        
        cursor.execute("SELECT COUNT(*) FROM hn_comments WHERE text_embedding IS NOT NULL")
        embedded_comments = cursor.fetchone()[0]
        
        return stories, comments, embedded_stories, embedded_comments


def get_recent_stories(conn, limit=5):
    """Get recent stories"""
    with conn.cursor() as cursor:
        cursor.execute("""
            SELECT id, title, score, TIMESTAMPDIFF(MINUTE, FROM_UNIXTIME(time), NOW()) as mins_ago
            FROM hn_stories
            ORDER BY time DESC
            LIMIT %s
        """, (limit,))
        return cursor.fetchall()


def display_status(conn):
    """Display comprehensive status"""
    clear_screen()
    
    print("=" * 80)
    print(f"SingleStore Hacker News Demo - Status Monitor")
    print(f"Time: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("=" * 80)
    print()
    
    # Data counts
    print("📊 Data Counts:")
    stories, comments, embedded_stories, embedded_comments = get_counts(conn)
    print(f"  Stories:           {stories:,} total, {embedded_stories:,} with embeddings")
    print(f"  Comments:          {comments:,} total, {embedded_comments:,} with embeddings")
    print()
    
    # Pipeline status
    print("🔄 Pipeline Status:")
    pipelines = get_pipeline_status(conn)
    for pipeline in pipelines:
        name, state, batch_state, interval, batches, parsed, written, error = pipeline
        print(f"  {name}:")
        print(f"    State: {state} | Batch: {batch_state}")
        print(f"    Batches: {batches:,} | Rows: {parsed:,} parsed, {written:,} written")
        if error:
            print(f"    ⚠️  Error: {error}")
    print()
    
    # Ingestion stats
    print("📈 Ingestion Statistics:")
    stats = get_stats(conn)
    for stat in stats:
        time_period, story_count, comment_count, avg_score = stat
        print(f"  {time_period}: {story_count} stories, {comment_count} comments (avg score: {avg_score:.1f})")
    print()
    
    # Recent stories
    print("📰 Recent Stories:")
    recent = get_recent_stories(conn)
    for story in recent:
        story_id, title, score, mins_ago = story
        print(f"  [{story_id}] {title[:60]}... (score: {score}, {mins_ago}m ago)")
    print()
    
    print("-" * 80)
    print("Press Ctrl+C to exit | Refreshing every 10 seconds...")


def main():
    """Main monitoring loop"""
    try:
        # Connect to SingleStore
        conn = s2.connect(**S2_CONFIG)
        
        # Monitor loop
        while True:
            display_status(conn)
            time.sleep(10)
            
    except KeyboardInterrupt:
        print("\n\nMonitoring stopped.")
        sys.exit(0)
    except Exception as e:
        print(f"\nError: {e}")
        sys.exit(1)
    finally:
        if 'conn' in locals():
            conn.close()


if __name__ == "__main__":
    main()
