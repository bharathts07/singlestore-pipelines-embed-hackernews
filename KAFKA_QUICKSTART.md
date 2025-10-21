# Cloud Kafka Quick Start Guide

Choose the easiest option for your demo setup:

## 🚀 Option 1: Confluent Cloud (Recommended - 5 minutes)

**Why**: Free tier, fastest setup, works out-of-the-box with SingleStore Cloud.

### Steps:

1. **Sign up**: https://confluent.cloud/signup (free $400 credits)

2. **Create Basic cluster**:
   - Cloud: AWS
   - Region: `us-east-1` (same as your SingleStore)
   - Name: `singlestore-hn-demo`

3. **Create topics**:
   - `hn-stories` (4 partitions)
   - `hn-comments` (4 partitions)

4. **Create API Key** (save these!):
   ```
   API Key: XXXXXXXXXXXXXXXXXXXX
   API Secret: YYYYYYYYYYYYYYYYYYYYYYYYYYYY
   ```

5. **Get Bootstrap Server** (from cluster overview):
   ```
   pkc-xxxxx.us-east-1.aws.confluent.cloud:9092
   ```

6. **Update `.env`**:
   ```bash
   # Add to your .env file:
   KAFKA_BOOTSTRAP_SERVERS=pkc-xxxxx.us-east-1.aws.confluent.cloud:9092
   KAFKA_API_KEY=your-api-key
   KAFKA_API_SECRET=your-api-secret
   KAFKA_TOPIC_STORIES=hn-stories
   KAFKA_TOPIC_COMMENTS=hn-comments
   ```

7. **Create pipelines**:
   ```bash
   source venv/bin/activate
   python scripts/setup_pipelines.py
   ```

✅ **Done!** Your pipelines should now be running.

---

## 🔧 Option 2: AWS MSK (30+ minutes)

**Why**: Full AWS integration, good for production.

### Quick Steps:

1. **AWS Console** → Search "MSK" → **Create cluster**

2. **Choose Quick Create**:
   - Name: `singlestore-hn-kafka`
   - Kafka version: 3.5.1
   - Broker: `kafka.t3.small` (2 brokers)
   - Authentication: Unauthenticated (for demo)

3. **Configure Security Group**:
   - EC2 → Security Groups → MSK security group
   - Inbound: Port `9092`, Source: `0.0.0.0/0` (or SingleStore IPs)

4. **Wait 15-20 minutes** for cluster to be Active

5. **Get Bootstrap Servers** (from cluster details)

6. **Create topics** (using AWS CLI or Console):
   ```bash
   aws kafka create-topic \
     --cluster-arn <your-arn> \
     --topic-name hn-stories \
     --partitions 4
   ```

7. **Update `.env`**:
   ```bash
   KAFKA_BOOTSTRAP_SERVERS=b-1.xxxxx.kafka.us-east-1.amazonaws.com:9092
   # No API keys needed for unauthenticated MSK
   ```

⚠️ **Note**: MSK requires public access setup (complex). See `AWS_MSK_SETUP.md` for full details.

---

## 📋 Comparison

| Feature | Confluent Cloud | AWS MSK |
|---------|----------------|---------|
| Setup time | 5 min | 30+ min |
| Free tier | ✅ $400 credits | ❌ ~$3-4/day |
| Networking | ✅ Auto | ❌ Manual |
| Public access | ✅ Built-in | ❌ Requires NLB/VPN |
| Best for | **Demos, Dev** | Production |

## 🎯 Recommendation

**For this demo**: Use **Confluent Cloud**
- Fastest setup
- Free tier
- No networking hassle
- Works immediately with SingleStore Cloud

**Full guides**:
- `CONFLUENT_CLOUD_SETUP.md` - Detailed Confluent setup
- `AWS_MSK_SETUP.md` - Detailed AWS MSK setup
