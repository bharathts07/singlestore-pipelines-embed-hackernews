"""Configuration for Hacker News Fetcher"""
import os
from dotenv import load_dotenv

load_dotenv()

# Hacker News API
HN_API_BASE_URL = "https://hacker-news.firebaseio.com/v0"
HN_FETCH_INTERVAL_SECONDS = int(os.getenv("HN_FETCH_INTERVAL_SECONDS", "30"))
HN_MAX_STORIES_PER_FETCH = int(os.getenv("HN_MAX_STORIES_PER_FETCH", "10"))
HN_MAX_COMMENTS_PER_STORY = int(os.getenv("HN_MAX_COMMENTS_PER_STORY", "20"))
HN_ENABLE_STORIES = os.getenv("HN_ENABLE_STORIES", "true").lower() == "true"
HN_ENABLE_COMMENTS = os.getenv("HN_ENABLE_COMMENTS", "true").lower() == "true"

# SingleStore Connection
SINGLESTORE_HOST = os.getenv("SINGLESTORE_HOST")
SINGLESTORE_PORT = int(os.getenv("SINGLESTORE_PORT", "3306"))
SINGLESTORE_USER = os.getenv("SINGLESTORE_USER")
SINGLESTORE_PASSWORD = os.getenv("SINGLESTORE_PASSWORD")
SINGLESTORE_DATABASE = os.getenv("SINGLESTORE_DATABASE", "hackernews_semantic")

# Logging
LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO")

# History tracking
HISTORY_FILE = ".hn_fetch_history.txt"
