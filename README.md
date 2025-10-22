# SingleStore EMBED_TEXT Demo
Real-time semantic search on Hacker News data using SingleStore's AI functions.

## Quick Start

1. **Configure Environment**
   ```bash
   cp .env.example .env
   # Edit .env with your SingleStore Cloud credentials
   ```

2. **Setup Database**
   ```bash
   python scripts/setup_database.py
   ```

3. **Start Data Ingestion**
   ```bash
   docker-compose up -d
   ```

4. **Launch Dashboard**
   ```bash
   cd dashboard && python app.py
   ```
   Open http://localhost:5000

## Architecture
```
Hacker News API → Python Fetcher → SingleStore Procedures → EMBED_TEXT() → Vector Storage
```

## Key Features
- Direct ingestion (no Kafka)
- EMBED_TEXT() generates 2048-dim vectors
- Semantic search with natural language queries
- Real-time dashboard

## Example Queries
```sql
CALL semantic_search_stories('database performance', 10);
CALL get_ingestion_stats();
```

## Requirements
- SingleStore Cloud with AI Functions
- Python 3.9+
- Docker

## License
MIT
