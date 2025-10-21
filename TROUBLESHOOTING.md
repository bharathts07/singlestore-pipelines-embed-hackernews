# Troubleshooting Guide

## Common Issues and Solutions

### 1. Python Package Installation Errors

**Symptoms:**
- `error: externally-managed-environment`
- Cannot install packages with pip
- "This environment is externally managed" error

**Solutions:**
```bash
# The setup script creates a virtual environment automatically
./scripts/setup.sh

# If you need to run Python scripts manually, always activate the venv first:
source venv/bin/activate

# Then run your Python commands:
python scripts/monitor.py
cd dashboard && python app.py

# To deactivate when done:
deactivate
```

**Common Causes:**
- macOS Python 3.12+ enforces PEP 668 (externally managed environments)
- Trying to install packages system-wide
- Not activating the virtual environment

**Note:** The `venv/` directory is automatically created by `./scripts/setup.sh` and is ignored by git.

### 2. Pipeline Not Starting

**Symptoms:**
- Pipeline shows `STOPPED` state
- No data being ingested

**Solutions:**
```sql
-- Check pipeline status
SELECT * FROM information_schema.PIPELINES;

-- Check for errors
SELECT PIPELINE_NAME, LAST_ERROR 
FROM information_schema.PIPELINES 
WHERE DATABASE_NAME = 'hn_semantic_search';

-- Restart pipeline
START PIPELINE hn_stories_pipeline;
START PIPELINE hn_comments_pipeline;
```

**Common Causes:**
- Kafka not running: `docker-compose ps kafka`
- Wrong Kafka configuration in pipeline
- Network connectivity issues

### 3. No Embeddings Generated

**Symptoms:**
- Data ingested but `title_embedding` or `text_embedding` columns are NULL
- Semantic search returns no results

**Solutions:**
```sql
-- Check if AI Functions are installed
SELECT cluster.EMBED_TEXT('test') AS test;

-- Verify embeddings are being generated
SELECT COUNT(*) as total, 
       COUNT(title_embedding) as with_embeddings 
FROM hn_stories;

-- Check stored procedure exists
SHOW PROCEDURES LIKE 'process_stories_batch';
```

**Common Causes:**
- AI Functions not installed in workspace
- Stored procedure not created
- Pipeline not configured with `INTO PROCEDURE`

### 4. Kafka Connection Errors

**Symptoms:**
- Pipeline shows "Connection refused" errors
- HN fetcher logs show Kafka errors

**Solutions:**
```bash
# Check Kafka is running
docker-compose ps kafka

# View Kafka logs
docker-compose logs kafka

# Restart Kafka services
docker-compose restart zookeeper kafka

# Verify topics exist
docker-compose exec kafka kafka-topics --bootstrap-server localhost:9092 --list
```

**Common Causes:**
- Zookeeper not started before Kafka
- Port 9092 already in use
- Docker network issues

### 5. Dashboard API Errors

**Symptoms:**
- Dashboard shows "Failed to load stats"
- Search returns errors

**Solutions:**
```bash
# Check dashboard logs
cd dashboard
python app.py  # View console output

# Test database connection
python -c "import singlestoredb as s2; print(s2.connect(host='your-host'))"

# Verify .env configuration
cat ../.env
```

**Common Causes:**
- Invalid SingleStore credentials in `.env`
- Database doesn't exist
- Network/firewall blocking connection

### 6. HN Fetcher Not Working

**Symptoms:**
- No new stories appearing
- Kafka topics empty

**Solutions:**
```bash
# Check fetcher logs
docker-compose logs hn-fetcher

# Verify Hacker News API
curl https://hacker-news.firebaseio.com/v0/topstories.json

# Restart fetcher
docker-compose restart hn-fetcher

# Check Kafka topics have data
docker-compose exec kafka kafka-console-consumer \
  --bootstrap-server localhost:9092 \
  --topic hn-stories \
  --from-beginning \
  --max-messages 5
```

**Common Causes:**
- HN API rate limiting (rare, no official limits)
- Kafka not ready when fetcher started
- Network connectivity issues

### 7. Slow Search Performance

**Symptoms:**
- Semantic search takes >5 seconds
- Dashboard feels sluggish

**Solutions:**
```sql
-- Check if indexes exist
SHOW INDEXES FROM hn_stories;
SHOW INDEXES FROM hn_comments;

-- Verify index usage
EXPLAIN SELECT * FROM hn_stories 
WHERE DOT_PRODUCT(title_embedding, cluster.EMBED_TEXT('AI')) > 0.7
ORDER BY DOT_PRODUCT(title_embedding, cluster.EMBED_TEXT('AI')) DESC 
LIMIT 20;

-- Rebuild indexes if needed
ALTER TABLE hn_stories DROP INDEX idx_title_embedding;
ALTER TABLE hn_stories ADD VECTOR INDEX idx_title_embedding (title_embedding) 
INDEX_TYPE IVF_PQFS;
```

**Common Causes:**
- Large dataset without proper indexes
- Cold cache (first query after restart)
- Network latency to SingleStore

### 8. Docker Compose Issues

**Symptoms:**
- Services won't start
- Port conflicts

**Solutions:**
```bash
# Check Docker is running
docker info

# View all services
docker-compose ps

# Stop all services
docker-compose down

# Remove volumes and restart fresh
docker-compose down -v
docker-compose up -d

# Check port availability
lsof -i :9092  # Kafka
lsof -i :8080  # Kafka UI
lsof -i :5000  # Dashboard
```

### 9. Memory/Performance Issues

**Symptoms:**
- Docker containers using too much memory
- System slowdown

**Solutions:**
```bash
# Check resource usage
docker stats

# Adjust Docker resource limits in docker-compose.yml
# Example:
# services:
#   kafka:
#     mem_limit: 2g
#     cpus: 2

# Reduce fetcher frequency in .env
HN_FETCH_INTERVAL_SECONDS=60  # Slower polling
```

## Verification Commands

### Quick Health Check
```bash
# Activate virtual environment first
source venv/bin/activate

# Check all services
docker-compose ps

# Check database connection
python -c "import singlestoredb as s2, os; from dotenv import load_dotenv; load_dotenv(); s2.connect(host=os.getenv('SINGLESTORE_HOST'), user=os.getenv('SINGLESTORE_USER'), password=os.getenv('SINGLESTORE_PASSWORD'))"

# Check data pipeline
python scripts/monitor.py
```

### Reset Everything
```bash
# Stop all services
docker-compose down -v

# Clear history files
rm -f fetcher/processed_*.json

# Rebuild and restart
./scripts/setup.sh
```

## Getting Help

1. Check logs: `docker-compose logs [service-name]`
2. Monitor status: `python3 scripts/monitor.py`
3. View Kafka UI: http://localhost:8080
4. Run health checks in SingleStore:
   ```sql
   SELECT COUNT(*) FROM hn_stories;
   SELECT STATE FROM information_schema.PIPELINES;
   ```

## Debug Mode

Enable verbose logging:

```bash
# Dashboard debug mode
cd dashboard
DEBUG=1 python app.py

# Fetcher debug mode
docker-compose logs -f hn-fetcher
```
