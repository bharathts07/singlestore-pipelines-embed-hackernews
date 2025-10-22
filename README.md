# SingleStore EMBED_TEXT Demo
Real-time semantic search on Hacker News data using SingleStore's AI functions.

## Prerequisites
- **SingleStore Cloud workspace** with AI Functions enabled ([Get free trial](https://www.singlestore.com/cloud-trial/))
- **Python 3.9+**
- **Docker Desktop** (running)

## Quick Start (5 Minutes)

### 1. Clone and Setup
```bash
# Clone the repository
git clone https://github.com/bharathts07/singlestore-pipelines-embed-hackernews.git
cd singlestore-embed-pipelines

# Create Python virtual environment
python3 -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install Python dependencies
pip install -r requirements.txt
```

### 2. Configure SingleStore Connection
```bash
# Copy environment template
cp .env.example .env

# Edit .env and update these required fields:
# SINGLESTORE_HOST=your-workspace-id.svc.singlestore.com
# SINGLESTORE_USER=admin
# SINGLESTORE_PASSWORD=your-password
```

**To find your connection details:**
- Go to [SingleStore Portal](https://portal.singlestore.com/)
- Select your workspace → Connect → SQL IDE
- Copy the host, user, and password

### 3. Create Database Schema
```bash
# Make sure virtual environment is activated
source venv/bin/activate  # If not already activated

# Run setup script (creates database, tables, procedures)
python3 scripts/setup_database.py
```

You should see:
```
✓ Connected successfully
✓ AI Functions are installed and working
✓ Successfully executed sql/01_schema.sql
✓ Successfully executed sql/02_procedures.sql
✓ Database setup completed successfully!
```

### 4. Start Data Ingestion
```bash
# Build and start the fetcher container
docker-compose up -d

# Watch the logs (Ctrl+C to exit)
docker-compose logs -f
```

You should see stories and comments being fetched and embedded.

### 5. Test Semantic Search
```bash
# Wait for some data to be collected (check with docker-compose logs -f)
# Then run a test search

python3 -c "
import singlestoredb as s2, os
from dotenv import load_dotenv
load_dotenv()

conn = s2.connect(
    host=os.getenv('SINGLESTORE_HOST'),
    port=int(os.getenv('SINGLESTORE_PORT', 3306)),
    user=os.getenv('SINGLESTORE_USER'),
    password=os.getenv('SINGLESTORE_PASSWORD'),
    database='hackernews_semantic'
)

with conn.cursor() as cur:
    # Note: semantic_search_stories takes 3 params: query, limit, min_score
    cur.execute(\"CALL semantic_search_stories('machine learning', 5, 0)\")
    results = cur.fetchall()
    print(f'Found {len(results)} results')
    for row in results:
        print(f'  - {row[1][:60]}... (score: {row[6]:.3f})')

conn.close()
"
```

### 6. Launch Dashboard (Optional)
```bash
# In a new terminal window
cd dashboard
../venv/bin/python3 app.py
```

Open http://localhost:5000 in your browser.

**If port 5000 is already in use:**
```bash
# Use a different port (e.g., 8080)
DASHBOARD_PORT=8080 ../venv/bin/python3 app.py
```
Then open http://localhost:8080 instead.

## Architecture
```
Hacker News API → Python Fetcher → SingleStore Procedures → EMBED_TEXT() → Vector Storage
```

## Useful Commands

**Monitor ingestion:**
```bash
source venv/bin/activate
python3 scripts/monitor.py
```

**Check data counts:**
```bash
source venv/bin/activate
python3 -c "
import singlestoredb as s2, os
from dotenv import load_dotenv
load_dotenv()

conn = s2.connect(
    host=os.getenv('SINGLESTORE_HOST'),
    port=int(os.getenv('SINGLESTORE_PORT', 3306)),
    user=os.getenv('SINGLESTORE_USER'),
    password=os.getenv('SINGLESTORE_PASSWORD'),
    database='hackernews_semantic'
)

with conn.cursor() as cur:
    cur.execute('SELECT COUNT(*) FROM hn_stories')
    stories = cur.fetchone()[0]
    cur.execute('SELECT COUNT(*) FROM hn_comments')
    comments = cur.fetchone()[0]
    print(f'Stories: {stories}, Comments: {comments}')

conn.close()
"
```

**Stop everything:**
```bash
docker-compose down
```

**Clean restart:**
```bash
# Stop containers
docker-compose down

# Drop database (clears all data)
source venv/bin/activate
python3 -c "
import singlestoredb as s2, os
from dotenv import load_dotenv
load_dotenv()

conn = s2.connect(
    host=os.getenv('SINGLESTORE_HOST'),
    port=int(os.getenv('SINGLESTORE_PORT', 3306)),
    user=os.getenv('SINGLESTORE_USER'),
    password=os.getenv('SINGLESTORE_PASSWORD')
)

with conn.cursor() as cur:
    cur.execute('DROP DATABASE IF EXISTS hackernews_semantic')
    print('✓ Database dropped')

conn.close()
"

# Recreate and restart
python3 scripts/setup_database.py
docker-compose up -d
```

## Example SQL Queries
```sql
-- Search stories by semantic meaning
CALL semantic_search_stories('database performance optimization', 10);

-- Search comments
CALL semantic_search_comments('machine learning best practices', 10);

-- Get ingestion statistics
CALL get_ingestion_stats();

-- Direct vector similarity search
SELECT 
    id, 
    title,
    DOT_PRODUCT(title_embedding, cluster.EMBED_TEXT('AI and databases')) as similarity
FROM hn_stories
WHERE title_embedding IS NOT NULL
ORDER BY similarity DESC
LIMIT 10;
```

## Troubleshooting

**"AI Functions not available"**
- Go to SingleStore Portal → AI & ML Functions
- Select your workspace and click "Install"

**"Module not found" errors**
- Make sure virtual environment is activated: `source venv/bin/activate`
- Reinstall dependencies: `pip install -r requirements.txt`

**"Connection failed"**
- Verify credentials in `.env` file
- Check workspace is active in SingleStore Portal
- Ensure your IP is allowlisted (Portal → Security)

**No data appearing**
- Check fetcher logs: `docker-compose logs -f`
- Verify Docker is running: `docker-compose ps`
- Check database connection from fetcher container

## Key Features
- **Direct ingestion** - No Kafka, no pipelines, just Python → Stored Procedures
- **EMBED_TEXT()** - Generates 2048-dimensional vectors automatically
- **Semantic search** - Natural language queries using vector similarity
- **Real-time** - Continuous ingestion from Hacker News API
- **Vector indexes** - IVF_PQFS indexes for fast similarity search

## License
MIT
