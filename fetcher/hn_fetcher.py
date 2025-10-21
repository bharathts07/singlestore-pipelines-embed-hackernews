"""
Hacker News to Kafka Data Fetcher
==================================

This service continuously polls the Hacker News Firebase API and publishes
stories and comments to Kafka topics for real-time ingestion into SingleStore.

Features:
- Fetches new stories from HN's newstories endpoint
- Recursively fetches comments for each story
- Publishes to separate Kafka topics (hn-stories, hn-comments)
- Tracks processed items to avoid duplicates
- Handles rate limiting and errors gracefully
- Logs all activity for monitoring

Author: SingleStore Demo
"""

import json
import logging
import time
import requests
from datetime import datetime
from typing import Dict, List, Set, Optional
from kafka import KafkaProducer
from kafka.errors import KafkaError

import config

# Configure logging
logging.basicConfig(
    level=getattr(logging, config.LOG_LEVEL),
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class HackerNewsFetcher:
    """
    Fetches data from Hacker News API and publishes to Kafka
    """
    
    def __init__(self):
        self.api_base = config.HN_API_BASE_URL
        self.processed_stories: Set[int] = set()
        self.processed_comments: Set[int] = set()
        
        # Initialize Kafka producer
        self.producer = KafkaProducer(
            bootstrap_servers=config.KAFKA_BOOTSTRAP_SERVERS,
            value_serializer=lambda v: json.dumps(v).encode('utf-8'),
            key_serializer=lambda k: str(k).encode('utf-8') if k else None,
            acks='all',  # Wait for all replicas to acknowledge
            retries=3,
            max_in_flight_requests_per_connection=1  # Ensure ordering
        )
        
        logger.info(f"Kafka producer initialized: {config.KAFKA_BOOTSTRAP_SERVERS}")
        
        # Load history of processed items
        self._load_history()
    
    def _load_history(self):
        """Load previously processed item IDs to avoid duplicates"""
        try:
            with open(config.HISTORY_FILE, 'r') as f:
                for line in f:
                    item_id = int(line.strip())
                    self.processed_stories.add(item_id)
                    self.processed_comments.add(item_id)
            logger.info(f"Loaded {len(self.processed_stories)} processed items from history")
        except FileNotFoundError:
            logger.info("No history file found, starting fresh")
        except Exception as e:
            logger.warning(f"Error loading history: {e}")
    
    def _save_to_history(self, item_id: int):
        """Save processed item ID to history file"""
        try:
            with open(config.HISTORY_FILE, 'a') as f:
                f.write(f"{item_id}\n")
        except Exception as e:
            logger.warning(f"Error saving to history: {e}")
    
    def fetch_item(self, item_id: int) -> Optional[Dict]:
        """
        Fetch a single item (story or comment) from HN API
        
        Args:
            item_id: The HN item ID to fetch
            
        Returns:
            Dict containing item data, or None if fetch fails
        """
        try:
            url = f"{self.api_base}/item/{item_id}.json"
            response = requests.get(url, timeout=10)
            response.raise_for_status()
            return response.json()
        except requests.exceptions.RequestException as e:
            logger.error(f"Error fetching item {item_id}: {e}")
            return None
    
    def fetch_new_stories(self) -> List[int]:
        """
        Fetch list of new story IDs from HN
        
        Returns:
            List of story IDs
        """
        try:
            url = f"{self.api_base}/newstories.json"
            response = requests.get(url, timeout=10)
            response.raise_for_status()
            return response.json()
        except requests.exceptions.RequestException as e:
            logger.error(f"Error fetching new stories: {e}")
            return []
    
    def publish_to_kafka(self, topic: str, key: int, value: Dict):
        """
        Publish a message to Kafka topic
        
        Args:
            topic: Kafka topic name
            key: Message key (item ID)
            value: Message value (item data)
        """
        try:
            future = self.producer.send(topic, key=key, value=value)
            # Block for 'synchronous' sends
            record_metadata = future.get(timeout=10)
            logger.debug(f"Published to {topic}: offset={record_metadata.offset}, key={key}")
        except KafkaError as e:
            logger.error(f"Error publishing to Kafka: {e}")
            raise
    
    def process_story(self, story_id: int) -> bool:
        """
        Fetch and publish a story to Kafka
        
        Args:
            story_id: The story ID to process
            
        Returns:
            True if successful, False otherwise
        """
        # Skip if already processed
        if story_id in self.processed_stories:
            return False
        
        # Fetch story data
        story = self.fetch_item(story_id)
        if not story:
            return False
        
        # Only process actual stories (not jobs, polls, etc.)
        if story.get('type') not in ['story', 'ask', 'show']:
            return False
        
        try:
            # Prepare story data for SingleStore
            story_data = {
                'id': story.get('id'),
                'title': story.get('title', ''),
                'url': story.get('url', ''),
                'score': story.get('score', 0),
                'by': story.get('by', ''),
                'time': story.get('time', 0),
                'descendants': story.get('descendants', 0),
                'type': story.get('type', 'story'),
                'text': story.get('text', '')
            }
            
            # Publish to Kafka
            self.publish_to_kafka(
                config.KAFKA_TOPIC_STORIES,
                story_id,
                story_data
            )
            
            # Mark as processed
            self.processed_stories.add(story_id)
            self._save_to_history(story_id)
            
            logger.info(f"Processed story {story_id}: {story.get('title', 'No title')[:50]}")
            
            # Process comments if enabled
            if config.HN_ENABLE_COMMENTS:
                self.process_comments(story, story_id)
            
            return True
            
        except Exception as e:
            logger.error(f"Error processing story {story_id}: {e}")
            return False
    
    def process_comments(self, story: Dict, story_id: int, parent_id: Optional[int] = None):
        """
        Recursively fetch and publish comments for a story
        
        Args:
            story: Story dict or comment dict containing 'kids' field
            story_id: Top-level story ID
            parent_id: Parent comment ID (None for top-level comments)
        """
        kids = story.get('kids', [])
        
        # Limit comments per story to avoid overwhelming the system
        if len(kids) > config.HN_MAX_COMMENTS_PER_STORY:
            kids = kids[:config.HN_MAX_COMMENTS_PER_STORY]
        
        for comment_id in kids:
            # Skip if already processed
            if comment_id in self.processed_comments:
                continue
            
            # Fetch comment
            comment = self.fetch_item(comment_id)
            if not comment:
                continue
            
            # Skip deleted or dead comments
            if comment.get('deleted') or comment.get('dead'):
                continue
            
            try:
                # Prepare comment data
                comment_data = {
                    'id': comment.get('id'),
                    'parent': parent_id if parent_id else story_id,
                    'story_id': story_id,
                    'by': comment.get('by', ''),
                    'time': comment.get('time', 0),
                    'type': 'comment',
                    'text': comment.get('text', '')
                }
                
                # Publish to Kafka
                self.publish_to_kafka(
                    config.KAFKA_TOPIC_COMMENTS,
                    comment_id,
                    comment_data
                )
                
                # Mark as processed
                self.processed_comments.add(comment_id)
                self._save_to_history(comment_id)
                
                logger.debug(f"Processed comment {comment_id} on story {story_id}")
                
                # Recursively process child comments (replies)
                if comment.get('kids'):
                    self.process_comments(comment, story_id, comment_id)
                    
            except Exception as e:
                logger.error(f"Error processing comment {comment_id}: {e}")
    
    def run(self):
        """
        Main loop: continuously fetch new stories and publish to Kafka
        """
        logger.info("Starting Hacker News fetcher...")
        logger.info(f"Fetch interval: {config.HN_FETCH_INTERVAL_SECONDS}s")
        logger.info(f"Stories enabled: {config.HN_ENABLE_STORIES}")
        logger.info(f"Comments enabled: {config.HN_ENABLE_COMMENTS}")
        
        iteration = 0
        
        while True:
            try:
                iteration += 1
                logger.info(f"=== Fetch iteration {iteration} ===")
                
                if not config.HN_ENABLE_STORIES:
                    logger.info("Story fetching disabled, sleeping...")
                    time.sleep(config.HN_FETCH_INTERVAL_SECONDS)
                    continue
                
                # Fetch new stories
                story_ids = self.fetch_new_stories()
                logger.info(f"Found {len(story_ids)} new stories")
                
                # Limit number of stories per fetch
                stories_to_fetch = story_ids[:config.HN_MAX_STORIES_PER_FETCH]
                
                # Process each story
                processed_count = 0
                for story_id in stories_to_fetch:
                    if self.process_story(story_id):
                        processed_count += 1
                        # Small delay between stories to be nice to HN API
                        time.sleep(0.5)
                
                logger.info(f"Processed {processed_count} new stories")
                
                # Flush Kafka producer
                self.producer.flush()
                
                # Sleep until next fetch
                logger.info(f"Sleeping for {config.HN_FETCH_INTERVAL_SECONDS}s...")
                time.sleep(config.HN_FETCH_INTERVAL_SECONDS)
                
            except KeyboardInterrupt:
                logger.info("Received shutdown signal")
                break
            except Exception as e:
                logger.error(f"Error in main loop: {e}", exc_info=True)
                time.sleep(10)  # Wait before retrying
        
        # Cleanup
        logger.info("Shutting down...")
        self.producer.close()


def main():
    """Entry point"""
    fetcher = HackerNewsFetcher()
    fetcher.run()


if __name__ == "__main__":
    main()
