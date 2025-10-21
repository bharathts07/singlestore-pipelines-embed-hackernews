# Confluent Cloud Setup Guide (Easiest Option!)

**Confluent Cloud** is the easiest way to get Kafka running for this demo. It's free for the first 400GB/month and requires no networking configuration.

## Why Confluent Cloud?

- ✅ **5-minute setup** (vs 30+ min for AWS MSK)
- ✅ **Free tier**: $400 credits + always-free basic cluster
- ✅ **No VPC/networking** configuration needed
- ✅ **Public endpoints** by default
- ✅ **Built-in monitoring** and UI
- ✅ **Works with SingleStore Cloud** out of the box

---

## Step-by-Step Setup

### Step 1: Sign Up (5 minutes)

1. Go to: **https://confluent.cloud/signup**
2. Sign up with email (Google/GitHub/email)
3. Choose **"Start with $400 free usage"**
4. Skip credit card (not required for free tier)

### Step 2: Create Kafka Cluster (2 minutes)

After login:

1. Click **"Create cluster"** or **"Add cluster"**
2. Choose **"Basic"** cluster (free tier eligible)
   - **Not** Standard or Dedicated
3. Configure:
   - **Cloud provider**: AWS (recommended, same as SingleStore)
   - **Region**: `us-east-1` (or closest to your SingleStore)
   - **Cluster name**: `singlestore-hn-demo`
4. Click **"Launch cluster"**
5. Wait ~2 minutes (much faster than AWS MSK!)

### Step 3: Create Topics (1 minute)

1. In your cluster, click **"Topics"** tab
2. Click **"Create topic"**
3. Create first topic:
   - **Topic name**: `hn-stories`
   - **Partitions**: `4`
   - Click **"Create with defaults"**
4. Repeat for second topic:
   - **Topic name**: `hn-comments`
   - **Partitions**: `4`

### Step 4: Create API Keys (1 minute)

1. Click **"API keys"** in left menu
2. Click **"Create key"**
3. Scope: **"Global access"** (for demo)
4. Click **"Next"**
5. **Download and save** the credentials:
   ```
   API Key: XXXXXXXXXXXXXXXXXXXX
   API Secret: YYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYY
   ```
   ⚠️ **Save these now!** You can't view the secret again.

### Step 5: Get Bootstrap Servers (1 minute)

1. Go to **"Cluster Overview"** or **"Cluster settings"**
2. Find **"Bootstrap server"**
3. Copy the endpoint, looks like:
   ```
   pkc-xxxxx.us-east-1.aws.confluent.cloud:9092
   ```

### Step 6: Update Your `.env` File

```bash
# Kafka Configuration (Confluent Cloud)
KAFKA_BOOTSTRAP_SERVERS=pkc-xxxxx.us-east-1.aws.confluent.cloud:9092
KAFKA_TOPIC_STORIES=hn-stories
KAFKA_TOPIC_COMMENTS=hn-comments

# Add these for authentication
KAFKA_API_KEY=your-api-key-from-step-4
KAFKA_API_SECRET=your-api-secret-from-step-4
```

### Step 7: Update Pipeline Configuration

The SQL pipelines need to use SASL authentication for Confluent Cloud.

Edit `sql/03_pipelines.sql` and update the CONFIG section:

```sql
CREATE PIPELINE hn_stories_pipeline AS
LOAD DATA KAFKA '${KAFKA_BOOTSTRAP_SERVERS}/${KAFKA_TOPIC_STORIES}'
    CONFIG '{
        "security.protocol": "SASL_SSL",
        "sasl.mechanism": "PLAIN",
        "sasl.username": "${KAFKA_API_KEY}",
        "sasl.password": "${KAFKA_API_SECRET}"
    }'
    
    BATCH_INTERVAL 5000
    MAX_PARTITIONS_PER_BATCH 4
    SKIP PARSER ERRORS
    
    INTO PROCEDURE process_stories_batch
    FORMAT JSON (...);
```

**Or** use a simpler approach - update `scripts/setup_pipelines.py` to handle authentication:

I'll create an updated version of the setup script that handles this automatically.

### Step 8: Test the Setup

```bash
# Activate virtual environment
source venv/bin/activate

# Create pipelines (should work now!)
python scripts/setup_pipelines.py
```

Expected output:
```
✓ Connected successfully
✓ Created pipeline: hn_stories_pipeline
✓ Created pipeline: hn_comments_pipeline
✓ All pipelines created successfully!
```

### Step 9: Start the Fetcher

```bash
# Build and start fetcher
docker-compose up -d hn-fetcher

# Check logs
docker-compose logs -f hn-fetcher
```

You should see:
```
Published story: ... to hn-stories
Published comment: ... to hn-comments
```

### Step 10: Verify in Confluent Cloud UI

1. Go to your cluster in Confluent Cloud
2. Click **"Topics"** → **"hn-stories"**
3. Click **"Messages"** tab
4. You should see incoming messages! 🎉

### Step 11: Verify in SingleStore

```sql
-- Check pipeline status
SELECT pipeline_name, state, rows_success, rows_error
FROM information_schema.PIPELINES;

-- Check if data is flowing
SELECT COUNT(*) FROM hn_stories_staging;
SELECT COUNT(*) FROM hn_stories;
```

---

## Update Fetcher Configuration

The fetcher also needs authentication. Update `fetcher/config.py`:

```python
# Kafka configuration
KAFKA_CONFIG = {
    'bootstrap_servers': os.getenv('KAFKA_BOOTSTRAP_SERVERS', 'localhost:9092'),
    'security_protocol': 'SASL_SSL',
    'sasl_mechanism': 'PLAIN',
    'sasl_plain_username': os.getenv('KAFKA_API_KEY'),
    'sasl_plain_password': os.getenv('KAFKA_API_SECRET'),
}
```

Then update `fetcher/hn_fetcher.py` to use this config:

```python
from kafka import KafkaProducer
from config import KAFKA_CONFIG

producer = KafkaProducer(
    **KAFKA_CONFIG,
    value_serializer=lambda v: json.dumps(v).encode('utf-8')
)
```

---

## Monitoring Your Cluster

### Confluent Cloud Dashboard

- **Messages/sec**: Real-time throughput
- **Consumer lag**: How far behind consumers are
- **Storage**: Data retained in topics

### Cost Tracking

- **Billing**: Menu → Billing & payment
- **Free tier**: 400GB/month free for Basic clusters
- **This demo uses**: <1GB/month (well within free tier)

---

## Troubleshooting

### "Connection refused" or "Authentication failed"

Check:
1. API Key and Secret are correct in `.env`
2. Bootstrap server URL is correct (no typos)
3. Security protocol is `SASL_SSL` not `PLAINTEXT`

### "Topics not found"

- Verify topics exist in Confluent Cloud UI
- Check topic names match exactly (case-sensitive)

### Pipelines not starting in SingleStore

```sql
-- Check pipeline errors
SELECT * FROM information_schema.PIPELINES_ERRORS 
ORDER BY error_time DESC LIMIT 10;

-- Check pipeline state
SELECT pipeline_name, state, error_msg 
FROM information_schema.PIPELINES;
```

### No data flowing

1. Check fetcher is running: `docker-compose ps`
2. Check fetcher logs: `docker-compose logs hn-fetcher`
3. Verify messages in Confluent Cloud UI → Topics → Messages
4. Check pipeline status in SingleStore

---

## Cost Comparison

| Option | Setup Time | Monthly Cost | Complexity |
|--------|-----------|--------------|------------|
| **Confluent Cloud** | 5 min | $0 (free tier) | ⭐ Easy |
| AWS MSK Provisioned | 30 min | ~$100 | ⭐⭐⭐ Hard |
| AWS MSK Serverless | 15 min | ~$20 | ⭐⭐ Medium |
| Local Kafka + Local S2 | 5 min | $0 | ⭐ Easy |

**Recommendation**: Use **Confluent Cloud** for this demo. It's free, fast, and works perfectly with SingleStore Cloud.

---

## Next Steps

Once everything is working:

1. **Start the dashboard**: `cd dashboard && python app.py`
2. **Test semantic search**: Search for "AI" or "Python"
3. **Monitor ingestion**: Watch `ingestion_stats` table
4. **Explore data**: Query with vector similarity

---

## Clean Up (When Done)

To avoid charges:

1. **Confluent Cloud**:
   - Clusters → Your cluster → Settings → **Delete cluster**
   - On free tier, you can keep it running indefinitely

2. **SingleStore Cloud**:
   - Keep it running (free starter workspace)
   - Or delete via SingleStore Portal

3. **Local Docker**:
   ```bash
   docker-compose down -v
   ```

---

## Support

- **Confluent Docs**: https://docs.confluent.io/cloud/current/
- **Slack**: Confluent Community Slack
- **Support**: support@confluent.io (even on free tier!)

**This is the easiest path for your demo!** 🚀
