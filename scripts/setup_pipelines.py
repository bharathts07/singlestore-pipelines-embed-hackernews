#!/usr/bin/env python3
"""
Pipelines Setup Script for SingleStore Hacker News Demo

This script creates the Kafka pipelines. It should be run after:
1. Database schema is created
2. Stored procedures are created
3. Kafka is running

Usage:
    python setup_pipelines.py

Prerequisites:
    - Database and procedures already created
    - Kafka running at configured bootstrap servers
"""

import os
import sys
import singlestoredb as s2
from dotenv import load_dotenv
import logging

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Load environment variables
load_dotenv()

# SingleStore connection configuration
S2_CONFIG = {
    "host": os.getenv("SINGLESTORE_HOST"),
    "port": int(os.getenv("SINGLESTORE_PORT", 3306)),
    "user": os.getenv("SINGLESTORE_USER"),
    "password": os.getenv("SINGLESTORE_PASSWORD"),
    "database": os.getenv("SINGLESTORE_DATABASE", "hackernews_semantic")
}

KAFKA_BOOTSTRAP_SERVERS = os.getenv("KAFKA_BOOTSTRAP_SERVERS", "localhost:9092")
KAFKA_TOPIC_STORIES = os.getenv("KAFKA_TOPIC_STORIES", "hn-stories")
KAFKA_TOPIC_COMMENTS = os.getenv("KAFKA_TOPIC_COMMENTS", "hn-comments")


def create_pipelines(conn):
    """Create Kafka pipelines"""
    logger.info("Creating Kafka pipelines...")
    
    with open('sql/03_pipelines.sql', 'r') as f:
        content = f.read()
    
    # Replace variables
    content = content.replace('${KAFKA_BOOTSTRAP_SERVERS}', KAFKA_BOOTSTRAP_SERVERS)
    content = content.replace('${KAFKA_TOPIC_STORIES}', KAFKA_TOPIC_STORIES)
    content = content.replace('${KAFKA_TOPIC_COMMENTS}', KAFKA_TOPIC_COMMENTS)
    
    # Split by semicolons (pipelines don't have nested semicolons like procedures)
    statements = [s.strip() for s in content.split(';') if s.strip()]
    
    with conn.cursor() as cursor:
        for stmt in statements:
            # Skip comments
            lines = stmt.split('\n')
            code_lines = [line for line in lines if not line.strip().startswith('--')]
            clean_stmt = '\n'.join(code_lines).strip()
            
            if not clean_stmt:
                continue
            
            # Log pipeline creation
            pipeline_name = 'unknown'
            if 'CREATE PIPELINE' in clean_stmt.upper():
                import re
                match = re.search(r'CREATE PIPELINE\s+(\w+)', clean_stmt, re.IGNORECASE)
                pipeline_name = match.group(1) if match else 'unknown'
                logger.info(f"  Creating pipeline: {pipeline_name}")
            
            try:
                cursor.execute(clean_stmt)
                if 'CREATE PIPELINE' in clean_stmt.upper():
                    logger.info(f"    ✓ Created {pipeline_name}")
            except Exception as e:
                error_msg = str(e)
                if 'already exists' in error_msg.lower():
                    logger.info(f"    ○ {pipeline_name} already exists (skipping)")
                else:
                    logger.error(f"    ✗ Failed to create pipeline")
                    logger.error(f"    Error: {e}")
                    raise
    
    conn.commit()


def main():
    """Main setup function"""
    logger.info("=" * 70)
    logger.info("SingleStore Pipelines Setup")
    logger.info("=" * 70)
    
    # Validate configuration
    if not S2_CONFIG["host"]:
        logger.error("SINGLESTORE_HOST not configured in .env file")
        sys.exit(1)
    
    # Connect to SingleStore
    logger.info(f"Connecting to SingleStore at {S2_CONFIG['host']}...")
    try:
        conn = s2.connect(**S2_CONFIG)
        logger.info("✓ Connected successfully")
    except Exception as e:
        logger.error(f"✗ Connection failed: {e}")
        sys.exit(1)
    
    # Create pipelines
    try:
        create_pipelines(conn)
        logger.info("✓ All pipelines created successfully")
    except Exception as e:
        logger.error(f"✗ Failed to create pipelines: {e}")
        logger.info("")
        logger.info("Troubleshooting:")
        logger.info("  1. Ensure Kafka is running: docker-compose ps kafka")
        logger.info("  2. Check Kafka bootstrap servers in .env")
        logger.info("  3. Verify Kafka topics exist: docker-compose exec kafka \\")
        logger.info("       kafka-topics --bootstrap-server localhost:9092 --list")
        sys.exit(1)
    
    # Success
    logger.info("=" * 70)
    logger.info("✓ Pipelines setup completed successfully!")
    logger.info("=" * 70)
    logger.info("")
    logger.info("Next steps:")
    logger.info("  1. Start HN fetcher: docker-compose up -d hn-fetcher")
    logger.info("  2. Monitor pipelines: SELECT * FROM information_schema.PIPELINES;")
    logger.info("  3. Start dashboard: cd dashboard && python app.py")
    logger.info("")
    
    conn.close()


if __name__ == "__main__":
    main()
