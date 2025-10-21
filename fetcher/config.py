"""
Configuration for Hacker News Fetcher
"""
import os
from dotenv import load_dotenv

load_dotenv()

# Hacker News API Configuration
HN_API_BASE_URL = "https://hacker-news.firebaseio.com/v0"
HN_FETCH_INTERVAL_SECONDS = int(os.getenv("HN_FETCH_INTERVAL_SECONDS", "30"))
HN_MAX_STORIES_PER_FETCH = int(os.getenv("HN_MAX_STORIES_PER_FETCH", "50"))
HN_MAX_COMMENTS_PER_STORY = int(os.getenv("HN_MAX_COMMENTS_PER_STORY", "50"))
HN_ENABLE_STORIES = os.getenv("HN_ENABLE_STORIES", "true").lower() == "true"
HN_ENABLE_COMMENTS = os.getenv("HN_ENABLE_COMMENTS", "true").lower() == "true"

# Kafka Configuration
KAFKA_BOOTSTRAP_SERVERS = os.getenv("KAFKA_BOOTSTRAP_SERVERS", "localhost:9092")
KAFKA_TOPIC_STORIES = os.getenv("KAFKA_TOPIC_STORIES", "hn-stories")
KAFKA_TOPIC_COMMENTS = os.getenv("KAFKA_TOPIC_COMMENTS", "hn-comments")

# Logging Configuration
LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO")

# Fetch history file to track processed items
HISTORY_FILE = ".hn_fetch_history.txt"
