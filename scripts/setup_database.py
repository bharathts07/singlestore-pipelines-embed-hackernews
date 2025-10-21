#!/usr/bin/env python3
"""
Database Setup Script for SingleStore Hacker News Semantic Search Demo

This script automates the setup of the SingleStore database schema,
stored procedures, and pipelines.

Usage:
    python setup_database.py

Prerequisites:
    - SingleStore workspace running
    - AI Functions installed in workspace
    - .env file configured with connection details
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
}

KAFKA_BOOTSTRAP_SERVERS = os.getenv("KAFKA_BOOTSTRAP_SERVERS", "localhost:9092")
KAFKA_TOPIC_STORIES = os.getenv("KAFKA_TOPIC_STORIES", "hn-stories")
KAFKA_TOPIC_COMMENTS = os.getenv("KAFKA_TOPIC_COMMENTS", "hn-comments")


def execute_sql_file(conn, filepath: str, replace_vars: dict = None):
    """Execute SQL commands from a file"""
    logger.info(f"Executing {filepath}...")
    
    try:
        with open(filepath, 'r') as f:
            sql_content = f.read()
        
        # Replace variables if provided
        if replace_vars:
            for key, value in replace_vars.items():
                sql_content = sql_content.replace(f"${{{key}}}", value)
        
        # Split into individual statements
        statements = [s.strip() for s in sql_content.split(';') if s.strip()]
        
        #  Execute statements in order
        with conn.cursor() as cursor:
            for i, statement in enumerate(statements):
                # Skip empty statements
                if not statement:
                    continue
                
                # Remove comment lines (lines starting with --)
                lines = statement.split('\n')
                code_lines = [line for line in lines if not line.strip().startswith('--')]
                clean_statement = '\n'.join(code_lines).strip()
                
                # Skip if nothing left after removing comments
                if not clean_statement:
                    continue
                
                # Log important statements
                stmt_preview = clean_statement[:80].replace('\n', ' ')
                if any(keyword in clean_statement.upper() for keyword in ['CREATE DATABASE', 'CREATE TABLE', 'ALTER TABLE', 'USE ', 'CREATE OR REPLACE VIEW']):
                    logger.info(f"  [{i}] {stmt_preview}...")
                
                try:
                    cursor.execute(clean_statement)
                except Exception as e:
                    error_msg = str(e)
                    # Ignore "already exists" errors
                    if 'already exists' in error_msg.lower() or 'duplicate key name' in error_msg.lower():
                        logger.debug(f"Skipping (already exists): {stmt_preview}...")
                        continue
                    # For debugging: show first 300 chars of problematic statement
                    if 'VIEW' in clean_statement.upper():
                        logger.error(f"VIEW statement (first 300 chars):\n{clean_statement[:300]}")
                    logger.error(f"Error executing statement: {clean_statement[:100]}...")
                    logger.error(f"Error: {e}")
                    raise
        
        logger.info(f"✓ Successfully executed {filepath}")
        return True
        
    except FileNotFoundError:
        logger.error(f"File not found: {filepath}")
        return False
    except Exception as e:
        logger.error(f"Error executing {filepath}: {e}")
        return False


def check_ai_functions(conn):
    """Check if AI Functions are installed"""
    logger.info("Checking AI Functions installation...")
    
    try:
        with conn.cursor() as cursor:
            cursor.execute("SELECT cluster.EMBED_TEXT('test') AS test")
            result = cursor.fetchone()
            if result:
                logger.info("✓ AI Functions are installed and working")
                return True
    except Exception as e:
        logger.error("✗ AI Functions not available")
        logger.error("Please install AI Functions in your workspace:")
        logger.error("  1. Go to SingleStore Portal")
        logger.error("  2. Navigate to AI > AI & ML Functions")
        logger.error("  3. Select your workspace")
        logger.error("  4. Click 'Install' in the AI Functions tab")
        return False


def main():
    """Main setup function"""
    logger.info("=" * 70)
    logger.info("SingleStore Hacker News Semantic Search Demo - Database Setup")
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
    
    # Check AI Functions
    if not check_ai_functions(conn):
        logger.error("Setup aborted. Please install AI Functions first.")
        sys.exit(1)
    
    # Execute schema file
    logger.info("Creating database schema...")
    if not execute_sql_file(conn, "sql/01_schema.sql"):
        logger.error("Setup failed at sql/01_schema.sql")
        sys.exit(1)
    
    # Close connection before calling subprocess
    conn.close()
    
    # Create stored procedures using specialized script
    logger.info("Creating stored procedures...")
    import subprocess
    result = subprocess.run(
        [sys.executable, "scripts/setup_procedures.py"],
        capture_output=True,
        text=True
    )
    if result.returncode != 0:
        logger.error("Failed to create stored procedures")
        logger.error(result.stderr)
        sys.exit(1)
    else:
        # Show output from procedures script
        for line in result.stdout.split('\n'):
            if line.strip():
                print(line)
    
    # Create pipelines (optional - requires Kafka)
    logger.info("Creating pipelines (requires Kafka)...")
    result = subprocess.run(
        [sys.executable, "scripts/setup_pipelines.py"],
        capture_output=True,
        text=True
    )
    if result.returncode != 0:
        logger.warning("⚠ Pipelines not created (Kafka may not be running)")
        logger.info("You can create them later by running:")
        logger.info("  1. Start Kafka: docker-compose up -d kafka zookeeper")
        logger.info("  2. Run: python scripts/setup_pipelines.py")
    else:
        # Show output from pipelines script
        for line in result.stdout.split('\n'):
            if line.strip():
                print(line)
    
    # Success
    logger.info("=" * 70)
    logger.info("✓ Database setup completed successfully!")
    logger.info("=" * 70)
    logger.info("")
    logger.info("Next steps:")
    logger.info("  1. Start Kafka: docker-compose up -d kafka zookeeper")
    logger.info("  2. Start HN fetcher: docker-compose up -d hn-fetcher")
    logger.info("  3. Start dashboard: cd dashboard && python app.py")
    logger.info("")
    logger.info("Monitor pipelines:")
    logger.info("  SELECT * FROM information_schema.PIPELINES;")
    logger.info("")
    
    # Close connection if still open
    try:
        if conn:
            conn.close()
    except:
        pass  # Already closed


if __name__ == "__main__":
    main()
