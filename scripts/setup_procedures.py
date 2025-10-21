#!/usr/bin/env python3
"""
Stored Procedures Setup Script for SingleStore Hacker News Demo

This script handles the special parsing needed for stored procedures
which contain semicolons inside BEGIN...END blocks.

Usage:
    python setup_procedures.py

Prerequisites:
    - Database schema already created
    - AI Functions installed
"""

import os
import sys
import re
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


def parse_procedures_file(filepath: str):
    """
    Parse SQL file containing stored procedures.
    Handles procedures with nested semicolons inside BEGIN...END blocks.
    """
    with open(filepath, 'r') as f:
        content = f.read()
    
    # Remove single-line comments
    content = re.sub(r'--[^\n]*\n', '\n', content)
    
    # Split into procedures by looking for CREATE OR REPLACE PROCEDURE
    # This regex finds procedure definitions
    procedure_pattern = r'(CREATE\s+(?:OR\s+REPLACE\s+)?PROCEDURE\s+\w+.*?END;)'
    procedures = re.findall(procedure_pattern, content, re.IGNORECASE | re.DOTALL)
    
    # Also capture any standalone statements (USE, etc.)
    statements = []
    
    # First, get any USE statements at the beginning
    use_match = re.search(r'^\s*(USE\s+\w+;)', content, re.IGNORECASE)
    if use_match:
        statements.append(('USE', use_match.group(1).strip()))
    
    # Then add all procedures
    for proc in procedures:
        # Extract procedure name
        name_match = re.search(r'PROCEDURE\s+(\w+)', proc, re.IGNORECASE)
        proc_name = name_match.group(1) if name_match else 'unknown'
        statements.append(('PROCEDURE', proc.strip(), proc_name))
    
    return statements


def execute_procedures(conn, statements):
    """Execute parsed procedures"""
    logger.info("Executing stored procedures...")
    
    with conn.cursor() as cursor:
        for stmt_type, *stmt_data in statements:
            if stmt_type == 'USE':
                sql = stmt_data[0]
                logger.info(f"  Switching to database...")
                try:
                    cursor.execute(sql)
                except Exception as e:
                    logger.warning(f"Database switch error (may be okay): {e}")
                    
            elif stmt_type == 'PROCEDURE':
                sql, proc_name = stmt_data
                logger.info(f"  Creating procedure: {proc_name}")
                try:
                    cursor.execute(sql)
                    logger.info(f"    ✓ Created {proc_name}")
                except Exception as e:
                    error_msg = str(e)
                    if 'already exists' in error_msg.lower():
                        logger.info(f"    ○ {proc_name} already exists (skipping)")
                    else:
                        logger.error(f"    ✗ Failed to create {proc_name}")
                        logger.error(f"    Error: {e}")
                        # Show first 200 chars of SQL for debugging
                        logger.debug(f"    SQL: {sql[:200]}...")
                        raise
    
    conn.commit()


def main():
    """Main setup function"""
    logger.info("=" * 70)
    logger.info("SingleStore Procedures Setup")
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
    
    # Parse procedures file
    try:
        statements = parse_procedures_file('sql/02_procedures.sql')
        logger.info(f"✓ Found {sum(1 for s in statements if s[0] == 'PROCEDURE')} procedures to create")
    except Exception as e:
        logger.error(f"✗ Failed to parse procedures file: {e}")
        sys.exit(1)
    
    # Execute procedures
    try:
        execute_procedures(conn, statements)
        logger.info("✓ All procedures created successfully")
    except Exception as e:
        logger.error(f"✗ Failed to create procedures: {e}")
        sys.exit(1)
    
    # Success
    logger.info("=" * 70)
    logger.info("✓ Stored procedures setup completed successfully!")
    logger.info("=" * 70)
    
    conn.close()


if __name__ == "__main__":
    main()
