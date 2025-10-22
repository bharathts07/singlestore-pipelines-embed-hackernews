#!/usr/bin/env python3
"""
Hacker News Fetcher - Direct Ingestion Mode (No Kafka)

This version calls SingleStore stored procedures directly,
bypassing Kafka entirely. Perfect for demos focused on EMBED_TEXT()
without the complexity of Kafka setup.

Architecture:
    HN API → Python → SingleStore Stored Procedures → EMBED_TEXT()
"""

import os
import sys
import time
import json
import logging
import requests
import singlestoredb as s2
from typing import Set, Optional, Dict, Any
from datetime import datetime
from dotenv import load_dotenv

# Load environment
load_dotenv()

# Configure logging
logging.basicConfig(
    level=os.getenv("LOG_LEVEL", "INFO"),
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Configuration
HN_API_BASE_URL = "https://hacker-news.firebaseio.com/v0"
HN_FETCH_INTERVAL = int(os.getenv("HN_FETCH_INTERVAL_SECONDS", "30"))
HN_MAX_STORIES = int(os.getenv("HN_MAX_STORIES_PER_FETCH", "10"))
HN_MAX_COMMENTS = int(os.getenv("HN_MAX_COMMENTS_PER_STORY", "20"))
HN_ENABLE_STORIES = os.getenv("HN_ENABLE_STORIES", "true").lower() == "true"
HN_ENABLE_COMMENTS = os.getenv("HN_ENABLE_COMMENTS", "true").lower() == "true"

# SingleStore connection
S2_CONFIG = {
    "host": os.getenv("SINGLESTORE_HOST"),
    "port": int(os.getenv("SINGLESTORE_PORT", 3306)),
    "user": os.getenv("SINGLESTORE_USER"),
    "password": os.getenv("SINGLESTORE_PASSWORD"),
    "database": os.getenv("SINGLESTORE_DATABASE", "hackernews_semantic")
}


class HNFetcherDirect:
    """Fetches HN data and inserts directly into SingleStore"""
    
    def __init__(self):
        self.processed_stories: Set[int] = set()
        self.processed_comments: Set[int] = set()
        self.session = requests.Session()
        
        # Connect to SingleStore
        logger.info(f"Connecting to SingleStore at {S2_CONFIG['host']}...")
        self.conn = s2.connect(**S2_CONFIG)
        logger.info("✓ Connected to SingleStore")
        
        # Test EMBED_TEXT() availability
        self._test_embed_text()
    
    def _test_embed_text(self):
        """Verify EMBED_TEXT() is available"""
        try:
            with self.conn.cursor() as cur:
                # Use cluster function syntax for cloud SingleStore
                cur.execute("SELECT cluster.EMBED_TEXT('test')")
                result = cur.fetchone()
                logger.info("✓ EMBED_TEXT() function is available")
        except Exception as e:
            logger.error("=" * 70)
            logger.error("✗ EMBED_TEXT() is NOT available on this SingleStore workspace")
            logger.error("=" * 70)
            logger.error("")
            logger.error("To enable AI Functions:")
            logger.error("  1. Go to: https://portal.singlestore.com")
            logger.error("  2. Select your workspace")
            logger.error("  3. Go to 'AI Functions' tab")
            logger.error("  4. Click 'Enable AI Functions'")
            logger.error("")
            logger.error("OR create a new workspace with AI Functions:")
            logger.error("  - Choose 'Standard' tier (not Starter)")
            logger.error("  - AI Functions are included")
            logger.error("")
            logger.error("Note: Starter workspaces do NOT support AI Functions")
            logger.error("")
            logger.error("=" * 70)
            logger.error(f"Technical error: {e}")
            logger.error("=" * 70)
            sys.exit(1)
    
    def fetch_item(self, item_id: int) -> Optional[Dict[str, Any]]:
        """Fetch a single item from HN API"""
        try:
            response = self.session.get(
                f"{HN_API_BASE_URL}/item/{item_id}.json",
                timeout=10
            )
            response.raise_for_status()
            return response.json()
        except Exception as e:
            logger.warning(f"Failed to fetch item {item_id}: {e}")
            return None
    
    def fetch_top_stories(self) -> list:
        """Fetch top story IDs from HN"""
        try:
            response = self.session.get(
                f"{HN_API_BASE_URL}/topstories.json",
                timeout=10
            )
            response.raise_for_status()
            return response.json()[:HN_MAX_STORIES]
        except Exception as e:
            logger.error(f"Failed to fetch top stories: {e}")
            return []
    
    def process_story(self, story: Dict[str, Any]):
        """Process a story by calling stored procedure"""
        try:
            with self.conn.cursor() as cur:
                cur.execute("""
                    CALL insert_story(%s, %s, %s, %s, %s, %s, %s, %s, %s)
                """, (
                    story.get('id'),
                    story.get('title', ''),
                    story.get('url', ''),
                    story.get('score', 0),
                    story.get('by', ''),
                    story.get('time', 0),
                    story.get('descendants', 0),
                    story.get('type', ''),
                    story.get('text', '')
                ))
                self.conn.commit()
                logger.info(f"✓ Processed story {story['id']}: {story.get('title', 'N/A')[:50]}")
                self.processed_stories.add(story['id'])
        except Exception as e:
            logger.error(f"Failed to process story {story.get('id')}: {e}")
    
    def process_comment(self, comment: Dict[str, Any], story_id: int):
        """Process a comment by calling stored procedure"""
        try:
            with self.conn.cursor() as cur:
                cur.execute("""
                    CALL insert_comment(%s, %s, %s, %s, %s, %s, %s)
                """, (
                    comment.get('id'),
                    comment.get('parent'),
                    story_id,
                    comment.get('by', ''),
                    comment.get('time', 0),
                    comment.get('type', ''),
                    comment.get('text', '')
                ))
                self.conn.commit()
                logger.debug(f"✓ Processed comment {comment['id']}")
                self.processed_comments.add(comment['id'])
        except Exception as e:
            logger.error(f"Failed to process comment {comment.get('id')}: {e}")
    
    def fetch_comments(self, story_id: int, comment_ids: list):
        """Fetch and process comments for a story"""
        count = 0
        for comment_id in comment_ids[:HN_MAX_COMMENTS]:
            if comment_id in self.processed_comments:
                continue
            
            comment = self.fetch_item(comment_id)
            if comment and comment.get('type') == 'comment':
                self.process_comment(comment, story_id)
                count += 1
        
        if count > 0:
            logger.info(f"  → Processed {count} comments for story {story_id}")
    
    def run_fetch_cycle(self):
        """Run one fetch cycle"""
        logger.info("=" * 60)
        logger.info(f"Starting fetch cycle at {datetime.now()}")
        
        # Fetch stories
        if HN_ENABLE_STORIES:
            story_ids = self.fetch_top_stories()
            logger.info(f"Fetched {len(story_ids)} top story IDs")
            
            new_stories = 0
            for story_id in story_ids:
                if story_id in self.processed_stories:
                    continue
                
                story = self.fetch_item(story_id)
                if not story or story.get('type') != 'story':
                    continue
                
                self.process_story(story)
                new_stories += 1
                
                # Fetch comments for this story
                if HN_ENABLE_COMMENTS and story.get('kids'):
                    self.fetch_comments(story_id, story['kids'])
            
            logger.info(f"Processed {new_stories} new stories")
        
        # Show stats
        with self.conn.cursor() as cur:
            cur.execute("SELECT COUNT(*) FROM hn_stories")
            total_stories = cur.fetchone()[0]
            cur.execute("SELECT COUNT(*) FROM hn_comments")
            total_comments = cur.fetchone()[0]
        
        logger.info(f"Database totals: {total_stories} stories, {total_comments} comments")
        logger.info(f"Next fetch in {HN_FETCH_INTERVAL} seconds...")
    
    def run(self):
        """Main loop"""
        logger.info("=" * 60)
        logger.info("HN Fetcher - Direct Ingestion Mode")
        logger.info("=" * 60)
        logger.info(f"SingleStore: {S2_CONFIG['host']}")
        logger.info(f"Fetch interval: {HN_FETCH_INTERVAL}s")
        logger.info(f"Max stories per fetch: {HN_MAX_STORIES}")
        logger.info(f"Max comments per story: {HN_MAX_COMMENTS}")
        logger.info(f"Stories enabled: {HN_ENABLE_STORIES}")
        logger.info(f"Comments enabled: {HN_ENABLE_COMMENTS}")
        logger.info("=" * 60)
        
        try:
            while True:
                try:
                    self.run_fetch_cycle()
                except Exception as e:
                    logger.error(f"Error in fetch cycle: {e}", exc_info=True)
                
                time.sleep(HN_FETCH_INTERVAL)
        except KeyboardInterrupt:
            logger.info("\nShutting down...")
        finally:
            if self.conn:
                self.conn.close()
                logger.info("Database connection closed")


if __name__ == "__main__":
    fetcher = HNFetcherDirect()
    fetcher.run()
