# Quick Start Guide

Get the demo running in under 10 minutes!

## Prerequisites

- ✅ Docker Desktop installed and running
- ✅ Python 3.9+ installed
- ✅ SingleStore Helios workspace (free tier works!)
- ✅ AI Functions installed in your workspace

## Step 1: Clone & Configure (2 minutes)

```bash
# Clone the repository
git clone https://github.com/bharathts07/singlestore-embed-pipelines.git
cd singlestore-embed-pipelines

# Create environment configuration
cp .env.example .env

# Edit .env with your SingleStore credentials
# You need: host, port, user, password
nano .env  # or use your favorite editor
```

**Get your SingleStore credentials:**
1. Go to [SingleStore Portal](https://portal.singlestore.com)
2. Select your workspace
3. Click "Connect" → "SQL IDE"
4. Copy the connection details

## Step 2: Run Setup (5 minutes)

```bash
# Make setup script executable
chmod +x scripts/setup.sh

# Run the automated setup
./scripts/setup.sh
```

This will:
- ✅ Install Python dependencies
- ✅ Create database schema
- ✅ Create stored procedures
- ✅ Set up pipelines
- ✅ Start Kafka & Zookeeper
- ✅ Start HN fetcher service

## Step 3: Start Dashboard (1 minute)

```bash
# In a new terminal
source venv/bin/activate  # Activate the virtual environment
cd dashboard
python app.py
```

Open your browser to **http://localhost:5000**

> **Note**: The setup script creates a Python virtual environment in `venv/`. Always activate it with `source venv/bin/activate` before running Python scripts.

## Step 4: Verify & Explore (2 minutes)

### Check Services
```bash
# View all running services
docker-compose ps

# Should see:
# ✓ zookeeper
# ✓ kafka  
# ✓ kafka-ui
# ✓ hn-fetcher
```

### Monitor Data Ingestion
```bash
# In a new terminal
source venv/bin/activate  # Activate virtual environment
python scripts/monitor.py
```

You should see:
- Stories and comments being ingested
- Embeddings being generated
- Recent activity updates

### Try Semantic Search

In the dashboard at http://localhost:5000:

1. **Wait 30-60 seconds** for first stories to be ingested
2. Try example searches:
   - "machine learning breakthroughs"
   - "startup funding advice"
   - "remote work challenges"
3. Compare Stories vs Comments tabs
4. Watch the real-time stats update

## Quick Commands

```bash
# View logs
docker-compose logs -f hn-fetcher

# Restart a service
docker-compose restart hn-fetcher

# Stop everything
docker-compose down

# Start everything again
docker-compose up -d
```

## Troubleshooting

### No data appearing?

```bash
# Check fetcher is running
docker-compose logs hn-fetcher

# Verify Kafka topics exist
docker-compose exec kafka kafka-topics --bootstrap-server localhost:9092 --list

# Restart pipelines in SingleStore
# In SQL IDE:
START PIPELINE hn_stories_pipeline;
START PIPELINE hn_comments_pipeline;
```

### Dashboard errors?

```bash
# Make sure virtual environment is activated
source venv/bin/activate

# Check .env configuration
cat .env

# Test database connection
python -c "import singlestoredb as s2; from dotenv import load_dotenv; import os; load_dotenv(); print('Testing...'); s2.connect(host=os.getenv('SINGLESTORE_HOST'), user=os.getenv('SINGLESTORE_USER'), password=os.getenv('SINGLESTORE_PASSWORD')); print('✓ Connected!')"
```

### Port conflicts?

If ports 5000, 8080, or 9092 are in use:

```bash
# Check what's using the port
lsof -i :5000

# Kill the process or change ports in docker-compose.yml
```

## Next Steps

- 📖 Read the full [README.md](README.md) for architecture details
- 🎯 Follow the [DEMO_SCRIPT.md](DEMO_SCRIPT.md) for presentation tips
- 🔧 Check [TROUBLESHOOTING.md](TROUBLESHOOTING.md) if issues arise
- 🔍 Explore [sql/04_queries.sql](sql/04_queries.sql) for more search examples

## Useful URLs

- **Dashboard**: http://localhost:5000
- **Kafka UI**: http://localhost:8080  
- **SingleStore Portal**: https://portal.singlestore.com

## Getting Help

1. Check the [TROUBLESHOOTING.md](TROUBLESHOOTING.md) guide
2. View logs: `docker-compose logs [service-name]`
3. Monitor status: `python3 scripts/monitor.py`
4. Open an issue on GitHub

---

**Ready to demo?** Follow the [DEMO_SCRIPT.md](DEMO_SCRIPT.md) for a step-by-step presentation guide!
