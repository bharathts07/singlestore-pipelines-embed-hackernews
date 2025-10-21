# SingleStore Cloud (Helios) Limitations

## Kafka Connectivity Issue

When using **SingleStore Cloud (Helios)**, the database cannot connect to Kafka running on `localhost` or in local Docker containers. This is because:

1. **SingleStore Cloud** runs in the cloud (AWS/GCP/Azure)
2. Your **Kafka instance** runs locally on your machine
3. The cloud database cannot reach `localhost:9092` on your machine

## Solutions

### Option 1: Use Cloud-Hosted Kafka (Recommended for Production)

Deploy Kafka to a cloud provider that SingleStore can reach:

- **Confluent Cloud**: Managed Kafka service
- **AWS MSK**: Amazon Managed Streaming for Apache Kafka
- **Azure Event Hubs**: Kafka-compatible service
- **Self-hosted on EC2/GCE**: Run Kafka on a cloud VM with public IP

### Option 2: Use SingleStore Self-Managed (Recommended for Local Development)

Instead of SingleStore Cloud, run SingleStore locally:

```bash
# Run SingleStore in Docker
docker run -d --name singlestore-dev \
  -p 3306:3306 -p 8080:8080 \
  -e ROOT_PASSWORD=password \
  singlestore/cluster-in-a-box:latest
```

Then connect to `localhost:3306` instead of the cloud endpoint.

### Option 3: Direct Data Ingestion (Bypass Pipelines)

For demos and testing, skip pipelines and insert data directly:

```python
# In fetcher/hn_fetcher.py, instead of sending to Kafka:
import singlestoredb as s2

conn = s2.connect(...)

# Directly call stored procedures
with conn.cursor() as cur:
    cur.execute("CALL process_stories_batch(?)", (json.dumps(story),))
```

### Option 4: Use ngrok for Kafka Tunneling (Development Only)

Expose your local Kafka to the internet temporarily:

```bash
# Install ngrok
brew install ngrok  # macOS
# or download from https://ngrok.com

# Expose Kafka port
ngrok tcp 9092

# Use the ngrok URL in .env
KAFKA_BOOTSTRAP_SERVERS=<ngrok-host>:<ngrok-port>
```

⚠️ **Warning**: This exposes Kafka to the public internet. Only for testing!

## Current Demo Configuration

This demo is currently configured with:
- **SingleStore**: Cloud (Helios) ✅
- **Kafka**: Local Docker ❌

This combination **will not work** for pipelines. The setup script will create:
- ✅ Database schema
- ✅ Stored procedures
- ❌ Pipelines (requires Kafka connectivity)

## Recommended Demo Setup

For a fully working demo, choose one of these:

### Quick Demo (Local Everything)
```bash
# 1. Run SingleStore locally
docker run -d --name singlestore -p 3306:3306 \
  -e ROOT_PASSWORD=password singlestore/cluster-in-a-box

# 2. Update .env to use localhost:3306
S2_HOST=localhost
S2_PORT=3306
S2_USER=root
S2_PASSWORD=password

# 3. Run setup
./scripts/setup.sh
```

### Production Demo (Cloud Everything)
```bash
# 1. Use SingleStore Cloud (current setup) ✅
# 2. Deploy Kafka to cloud (Confluent, MSK, etc.)
# 3. Update .env with cloud Kafka endpoint
# 4. Run setup
./scripts/setup.sh
```

## Files to Modify

If you want to bypass pipelines for direct ingestion:

1. **fetcher/hn_fetcher.py**: Remove Kafka producer, add direct DB calls
2. **sql/03_pipelines.sql**: Not needed
3. **docker-compose.yml**: Remove kafka/zookeeper services

See `DIRECT_INGESTION_MODE.md` for detailed instructions (to be created).
