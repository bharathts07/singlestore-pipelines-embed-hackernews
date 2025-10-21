# SingleStore Pipelines + EMBED_TEXT() Demo
## Real-Time Semantic Search on Hacker News Stories & Comments

This demo showcases the power of **SingleStore Pipelines** combined with the **EMBED_TEXT() AI function** for real-time semantic search on Hacker News data.

> **🚀 Quick Start**: New to this demo? See [QUICKSTART.md](QUICKSTART.md) for a 10-minute setup guide!

## 🎯 What This Demo Shows

1. **Real-Time Data Ingestion**: Hacker News stories and comments streaming through Kafka into SingleStore
2. **Automatic Embedding Generation**: EMBED_TEXT() AI function generates vector embeddings during ingestion
3. **Semantic Search**: Natural language queries finding relevant content based on meaning, not just keywords
4. **Live Dashboard**: Real-time visualization of data flow and semantic search interface

### Example Semantic Queries

- Query: "database performance" → Matches: "query optimization", "indexing strategies", "SQL tuning"
- Query: "machine learning infrastructure" → Matches: "ML ops", "model deployment", "training at scale"
- Query: "startup funding" → Matches: "Series A", "venture capital", "angel investors"

## 📚 Documentation

- **[QUICKSTART.md](QUICKSTART.md)** - Get started in 10 minutes
- **[DEMO_SCRIPT.md](DEMO_SCRIPT.md)** - Step-by-step presentation guide
- **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)** - Common issues and solutions

## 🏗️ Architecture

```
┌─────────────────┐
│ Hacker News API │  (Firebase API - no rate limits)
└────────┬────────┘
         │ Python Fetcher (polls every 30s)
         ↓
┌─────────────────┐
│  Kafka Topics   │  (hn-stories, hn-comments)
└────────┬────────┘
         │ SingleStore Pipelines
         ↓
┌─────────────────────────────────────────┐
│  Stored Procedures                      │
│  • Batch processing                     │
│  • EMBED_TEXT() calls                   │
│  • Insert with embeddings               │
└────────┬────────────────────────────────┘
         ↓
┌─────────────────────────────────────────┐
│  SingleStore Tables                     │
│  • hn_stories (with vector embeddings)  │
│  • hn_comments (with vector embeddings) │
│  • Vector indexes for fast search       │
└────────┬────────────────────────────────┘
         │
         ↓
┌─────────────────┐
│  Web Dashboard  │  (Real-time monitoring + Semantic Search)
└─────────────────┘
```

## 📋 Prerequisites

1. **SingleStore Workspace**:
   - SingleStore Helios account (or self-managed cluster)
   - **AI Functions installed** (required for EMBED_TEXT())
   - Connection details (host, port, username, password)

2. **Local Development**:
   - Docker & Docker Compose (for Kafka)
   - Python 3.9+ 
   - Git

## 🚀 Quick Start

### Step 1: Clone and Setup

```bash
git clone <repo-url>
cd singlestore-embed-pipelines

# Copy environment template
cp .env.example .env

# Edit .env with your SingleStore credentials
nano .env
```

### Step 2: Install AI Functions in SingleStore

```sql
-- In SingleStore Portal or Studio:
-- Navigate to: AI > AI & ML Functions
-- Select your workspace → AI Functions tab → Install
-- Review and Deploy
```

### Step 3: Start Kafka

```bash
docker-compose up -d kafka zookeeper
```

### Step 4: Setup Database Schema

```bash
# Activate virtual environment (created by setup.sh)
source venv/bin/activate

# Create database and tables
python scripts/setup_database.py
```

This will:
- Create database `hackernews_semantic`
- Create tables with vector columns
- Create stored procedures
- Create and start pipelines

### Step 5: Start Data Fetcher

```bash
# In a new terminal
docker-compose up -d hn-fetcher

# Or run locally:
cd fetcher
pip install -r requirements.txt
python hn_fetcher.py
```

### Step 6: Launch Dashboard

```bash
# Make sure virtual environment is activated
source venv/bin/activate

cd dashboard
python app.py
```

Open browser: http://localhost:5000

> **Note**: The setup script creates a Python virtual environment to avoid conflicts with system packages. Always activate it with `source venv/bin/activate` before running Python commands.

## 📊 Dashboard Features

### Real-Time Ingestion Monitor
- Live counter of stories/comments ingested
- Recent items with timestamps
- Pipeline health and status
- Ingestion rate graphs

### Semantic Search Interface
- Natural language search box
- Results with similarity scores
- Side-by-side keyword vs semantic comparison
- Highlighting of semantic matches

## 🗄️ Database Schema

### Stories Table
```sql
CREATE TABLE hn_stories (
    id BIGINT PRIMARY KEY,
    title TEXT,
    url TEXT,
    score INT,
    by VARCHAR(255),
    time DATETIME,
    text TEXT,
    title_embedding VECTOR(1536),      -- Embedding of title
    combined_embedding VECTOR(1536),   -- Embedding of title + text
    created_at DATETIME DEFAULT NOW(),
    VECTOR INDEX ivf_stories_title (title_embedding),
    VECTOR INDEX ivf_stories_combined (combined_embedding),
    SORT KEY (time DESC, score DESC)
);
```

### Comments Table
```sql
CREATE TABLE hn_comments (
    id BIGINT PRIMARY KEY,
    parent_id BIGINT,
    story_id BIGINT,
    text TEXT,
    by VARCHAR(255),
    time DATETIME,
    text_embedding VECTOR(1536),
    created_at DATETIME DEFAULT NOW(),
    VECTOR INDEX ivf_comments (text_embedding),
    SHARD KEY (story_id),
    KEY (parent_id),
    KEY (story_id)
);
```

## 🔍 Example Queries

### Semantic Search on Stories

```sql
-- Search for content about database performance
SET @query = 'database performance optimization';
SET @query_embedding = cluster.EMBED_TEXT(@query);

SELECT 
    id, 
    title, 
    score,
    DOT_PRODUCT(title_embedding, @query_embedding) AS similarity
FROM hn_stories
WHERE title_embedding IS NOT NULL
ORDER BY similarity DESC
LIMIT 10;
```

### Semantic Search on Comments

```sql
-- Find comments discussing machine learning
SET @query = 'machine learning deployment challenges';
SET @query_embedding = cluster.EMBED_TEXT(@query);

SELECT 
    c.id,
    c.text,
    s.title AS story_title,
    DOT_PRODUCT(c.text_embedding, @query_embedding) AS similarity
FROM hn_comments c
JOIN hn_stories s ON c.story_id = s.id
WHERE c.text_embedding IS NOT NULL
ORDER BY similarity DESC
LIMIT 10;
```

### Hybrid Search (Semantic + Metadata Filtering)

```sql
-- Find highly-scored stories about startups (semantic)
SET @query_embedding = cluster.EMBED_TEXT('startup funding and growth strategies');

SELECT 
    id,
    title,
    score,
    by,
    DOT_PRODUCT(title_embedding, @query_embedding) AS similarity
FROM hn_stories
WHERE score > 100
  AND title_embedding IS NOT NULL
ORDER BY similarity DESC
LIMIT 20;
```

## 📈 Monitoring

### Pipeline Status

```sql
-- Check pipeline status
SELECT 
    pipeline_name,
    state,
    batches_success,
    batches_error,
    rows_success,
    rows_error
FROM information_schema.PIPELINES
WHERE database_name = 'hackernews_semantic';
```

### Recent Ingestion Activity

```sql
-- Last 10 stories ingested
SELECT id, title, score, created_at
FROM hn_stories
ORDER BY created_at DESC
LIMIT 10;

-- Ingestion rate (stories per minute)
SELECT 
    DATE_FORMAT(created_at, '%Y-%m-%d %H:%i:00') AS minute,
    COUNT(*) AS stories_ingested
FROM hn_stories
WHERE created_at >= NOW() - INTERVAL 1 HOUR
GROUP BY minute
ORDER BY minute DESC;
```

## 🎨 Customization

### Adjust Embedding Model

Edit `sql/02_procedures.sql` to use different embedding models:

```sql
-- Options: 'openai-text-embed-large', 'openai-text-embed-small', etc.
cluster.EMBED_TEXT(text_column, 'openai-text-embed-large')
```

### Adjust Fetcher Frequency

Edit `fetcher/config.py`:

```python
FETCH_INTERVAL_SECONDS = 30  # Change polling frequency
MAX_STORIES_PER_FETCH = 50   # Stories to fetch each time
```

### Adjust Pipeline Batch Size

```sql
ALTER PIPELINE hn_stories_pipeline 
SET MAX_PARTITIONS_PER_BATCH = 1,
    BATCH_INTERVAL = 5000;  -- milliseconds
```

## 🛠️ Troubleshooting

### AI Functions Not Found

```
ERROR: FUNCTION cluster.EMBED_TEXT does not exist
```

**Solution**: Install AI Functions in SingleStore Portal:
- Navigate to AI > AI & ML Functions
- Select workspace → Install AI Functions

### Pipeline Errors

```sql
-- Check pipeline errors
SELECT * FROM information_schema.PIPELINES_ERRORS
WHERE pipeline_name LIKE 'hn_%'
ORDER BY error_time DESC;
```

### Kafka Connection Issues

```bash
# Check Kafka is running
docker-compose ps

# View Kafka logs
docker-compose logs kafka

# Test Kafka connection
docker-compose exec kafka kafka-topics.sh --list --bootstrap-server localhost:9092
```

### Embedding Generation is Slow

**Solutions**:
1. Reduce batch size in pipelines
2. Use CTEs to filter before embedding
3. Consider embedding only titles (not full text) for faster processing

## 📚 Additional Resources

- [SingleStore Pipelines Documentation](https://docs.singlestore.com/cloud/load-data/about-singlestore-pipelines/)
- [SingleStore AI Functions](https://docs.singlestore.com/cloud/ai-services/ai-ml-functions/ai-functions/)
- [Vector Search in SingleStore](https://docs.singlestore.com/cloud/developer-resources/functional-extensions/working-with-vector-data/)
- [Hacker News API](https://github.com/HackerNews/API)

## 📄 License

MIT License - See LICENSE file for details

## 🤝 Contributing

Contributions welcome! Please feel free to submit a Pull Request.

## 💡 Demo Tips for Presentation

1. **Start with clean database** to show ingestion from zero
2. **Have interesting queries ready** that show semantic understanding
3. **Compare keyword vs semantic search** side-by-side
4. **Show real-time dashboard** with live data flowing in
5. **Highlight the pipeline efficiency** - no triggers needed!

---

Built with ❤️ using SingleStore, Kafka, and Python
