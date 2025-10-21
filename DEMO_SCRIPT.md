# Demo Script

This guide provides a step-by-step script for presenting the SingleStore Hacker News Semantic Search demo.

## Pre-Demo Checklist (5 minutes before)

- [ ] All services running: `docker-compose ps`
- [ ] Data ingested: Check monitor shows >100 stories
- [ ] Dashboard accessible: http://localhost:5000
- [ ] Kafka UI accessible: http://localhost:8080
- [ ] Example searches tested

## Demo Flow (15-20 minutes)

### 1. Introduction (2 minutes)

**Script:**
> "Today I'm demonstrating the power of SingleStore Pipelines combined with the EMBED_TEXT() AI function for real-time semantic search. We'll be analyzing Hacker News stories and comments as they come in, automatically generating vector embeddings, and performing intelligent semantic searches."

**Key Points:**
- Real-time ingestion from Hacker News
- Automatic embedding generation
- Sub-second semantic search queries

### 2. Architecture Overview (3 minutes)

**Open:** `README.md` architecture diagram

**Script:**
> "The architecture is straightforward but powerful:
> 1. A Python service polls the Hacker News API every 30 seconds
> 2. New stories and comments are published to Kafka topics
> 3. SingleStore Pipelines consume from Kafka in real-time
> 4. Stored procedures call EMBED_TEXT() to generate 1536-dimension vectors
> 5. Data is immediately available for semantic search"

**Show:** Kafka UI at http://localhost:8080
- Point out `hn-stories` and `hn-comments` topics
- Show message count increasing

**Navigate to:** Topics → hn-stories → Messages
- Show sample message structure

### 3. Pipeline Demonstration (4 minutes)

**Open:** SingleStore Portal or SQL editor

**Run:**
```sql
-- Show pipeline status
SELECT 
    PIPELINE_NAME,
    STATE,
    BATCH_COUNT,
    ROWS_PARSED,
    ROWS_WRITTEN
FROM information_schema.PIPELINES
WHERE DATABASE_NAME = 'hn_semantic_search';
```

**Script:**
> "Our pipelines are actively running, processing batches every 5 seconds. Notice the rows being continuously written. Let's look at the data..."

**Run:**
```sql
-- Show recent ingestion
CALL get_ingestion_stats();
```

**Run:**
```sql
-- Show sample data with embeddings
SELECT 
    id,
    title,
    score,
    LENGTH(title_embedding) as embedding_size,
    FROM_UNIXTIME(time) as posted_at
FROM hn_stories 
ORDER BY time DESC 
LIMIT 5;
```

**Script:**
> "Each story has a 1536-dimension vector embedding generated automatically by EMBED_TEXT(). These vectors capture the semantic meaning of the text, not just keywords."

### 4. Semantic Search Demo (6 minutes)

**Open:** Dashboard at http://localhost:5000

**Script:**
> "Now for the exciting part - semantic search. Traditional keyword search requires exact matches. Semantic search understands meaning and context."

#### Search Example 1: Basic Semantic Search
**Type:** "artificial intelligence breakthroughs"

**Script:**
> "Look at these results - we're finding stories about AI, ML, neural networks, even though they might not use these exact words. The similarity scores show how closely related each story is to our query."

**Point out:**
- Similarity scores (0.0-1.0)
- Diverse but relevant results
- Both Stories and Comments tabs

#### Search Example 2: Concept Search
**Type:** "work life balance burnout"

**Script:**
> "Here we're searching for a concept - work-life balance and burnout. Notice we're finding discussions about remote work, startup culture, mental health - all semantically related."

#### Search Example 3: Technical Query
**Type:** "database performance optimization"

**Script:**
> "For technical topics, semantic search shines. We're finding discussions about query optimization, indexes, caching, connection pooling - all related concepts that might use different terminology."

#### Search Example 4: Compare with Comments
**Type:** "kubernetes deployment strategies"

**Switch to Comments tab**

**Script:**
> "We can search both stories and comments. Comments often have deeper technical discussions and alternative perspectives."

### 5. Real-Time Demonstration (3 minutes)

**Open:** Monitor script in terminal
```bash
python3 scripts/monitor.py
```

**Script:**
> "This monitor shows our system in real-time. Watch the counts increase as new stories arrive."

**Wait for refresh cycle, point out:**
- Row counts increasing
- Pipeline processing batches
- Recent stories appearing

**In Dashboard:**
- Scroll to "Recent Activity" section
- Show stories appearing in real-time

**Script:**
> "These stories are being ingested, embedded, and made searchable within seconds. That's the power of SingleStore Pipelines."

### 6. Under the Hood (2 minutes)

**Open:** `sql/02_procedures.sql`

**Script:**
> "The magic happens in our stored procedures. Here's the key line:"

**Show:**
```sql
SET batch.title_embedding = cluster.EMBED_TEXT(
    CAST(COALESCE(batch.title, '') AS TEXT),
    'text-embedding-3-small'
);
```

**Script:**
> "EMBED_TEXT() is a SingleStore AI function that calls OpenAI's embedding API. It returns a 1536-dimension vector that represents the semantic meaning of the text. We use the pipeline INTO PROCEDURE pattern because embeddings must be generated during the transformation phase, not extraction."

**Open:** `sql/01_schema.sql`

**Show:**
```sql
CREATE VECTOR INDEX idx_title_embedding (title_embedding) 
INDEX_TYPE IVF_PQFS;
```

**Script:**
> "Vector indexes enable fast approximate nearest neighbor search on millions of embeddings. SingleStore uses IVF_PQFS - Inverted File with Product Quantization Fast Scan - for optimal performance."

### 7. Closing & Q&A (2 minutes)

**Script:**
> "To summarize what we've built:
> - Real-time ingestion with SingleStore Pipelines
> - Automatic embedding generation with EMBED_TEXT()
> - Sub-second semantic search on streaming data
> - Production-ready architecture with monitoring
> 
> All of this is open source in the GitHub repo. The entire stack - from Kafka to the dashboard - can be deployed with one command: `./scripts/setup.sh`"

**Key Takeaways:**
1. Pipelines enable true real-time data ingestion
2. EMBED_TEXT() brings AI capabilities directly into your database
3. Vector indexes make semantic search fast and scalable
4. Combined, they create a powerful semantic search platform

## Demo Tips

### If Things Go Wrong

**Pipeline stopped:**
```sql
START PIPELINE hn_stories_pipeline;
```

**No results:**
- Check data exists: `SELECT COUNT(*) FROM hn_stories;`
- Verify embeddings: `SELECT COUNT(*) FROM hn_stories WHERE title_embedding IS NOT NULL;`

**Dashboard down:**
```bash
cd dashboard && python app.py
```

### Pro Tips

1. **Have backup queries ready** - Pre-test searches that you know return good results
2. **Keep monitor running** - Shows the system is live
3. **Open Kafka UI beforehand** - Browsers can be slow loading it first time
4. **Pre-load SQL queries** - Keep them in a text file for quick copy-paste
5. **Have fresh data** - Restart fetcher if needed: `docker-compose restart hn-fetcher`

### Extended Demo Ideas

**For technical audiences:**
- Show the actual vector dimensions in SQL
- Demonstrate different similarity thresholds
- Explain IVF_PQFS index structure
- Compare with traditional keyword search

**For business audiences:**
- Focus on use cases: customer support, content discovery, recommendation systems
- Emphasize real-time aspect and business value
- Show monitoring and operational visibility

**For data scientists:**
- Discuss embedding models (text-embedding-3-small vs large)
- Show similarity score distributions
- Explain vector search tradeoffs (speed vs accuracy)

## After the Demo

**Share resources:**
- GitHub repository
- SingleStore documentation links
- Setup guide for their own environment

**Collect feedback:**
- What use cases do they have?
- What questions remain?
- What would they build with this?
