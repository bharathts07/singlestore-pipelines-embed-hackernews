# AWS MSK (Managed Streaming for Apache Kafka) Setup Guide

This guide will help you set up AWS MSK to work with SingleStore Cloud for the Hacker News semantic search demo.

## Prerequisites

- AWS Account with billing enabled
- AWS CLI installed (optional but recommended)
- Your SingleStore Cloud endpoint (already configured in `.env`)

## Step-by-Step Setup

### Step 1: Install AWS CLI (Optional but Recommended)

```bash
# macOS
brew install awscli

# Configure AWS CLI with your credentials
aws configure
# Enter: Access Key ID, Secret Access Key, Region (e.g., us-east-1)
```

### Step 2: Create MSK Cluster (AWS Console Method)

#### 2.1 Navigate to MSK Service

1. Login to [AWS Console](https://console.aws.amazon.com)
2. Search for **"MSK"** or **"Managed Streaming for Apache Kafka"**
3. Click **"Create cluster"**

#### 2.2 Quick Create (Recommended for Demo)

Choose **"Quick create"** for fastest setup:

**Configuration:**
- **Cluster name**: `singlestore-hn-kafka`
- **Kafka version**: `3.5.1` (latest stable)
- **Cluster type**: **Provisioned** (not Serverless, for easier public access)
- **Broker type**: `kafka.t3.small` (cheapest option, ~$0.06/hour)
- **Number of brokers**: `2` (minimum)
- **Storage per broker**: `100 GB` (you'll use <1 GB for this demo)

**Networking:**
- **VPC**: Select your default VPC or create new
- **Availability Zones**: Select 2 AZs
- **Subnets**: Select public subnets (important for SingleStore access)
- **Security group**: Create new or select existing

**Access control:**
- **Authentication**: **Unauthenticated access** (for demo; use IAM for production)
- **Encryption**: TLS encryption (required)

**Click "Create cluster"** - takes ~15-20 minutes

#### 2.3 Configure Security Group for Public Access

While cluster is creating, configure security:

1. Go to **EC2 → Security Groups**
2. Find the security group attached to your MSK cluster
3. Edit **Inbound Rules**:
   - **Type**: Custom TCP
   - **Port**: `9094` (TLS) or `9092` (plaintext)
   - **Source**: `0.0.0.0/0` (for demo) or SingleStore Cloud IP ranges (production)
   - Click **Save rules**

#### 2.4 Enable Public Access (Critical!)

MSK clusters are private by default. To allow SingleStore Cloud to connect:

**Option A: Public Access via Proxy (Recommended)**

Use AWS Network Load Balancer:
1. Create NLB in same VPC
2. Target MSK broker endpoints
3. Expose port 9094 publicly
4. Use NLB DNS name in SingleStore

**Option B: MSK Serverless with IAM (Simpler for demos)**

Go back and choose **Serverless** instead:
- Automatically gets public endpoint
- Built-in IAM authentication
- More expensive but simpler networking

**Option C: VPC Peering (Production)**

Set up VPC peering between AWS and SingleStore Cloud VPC (complex, requires SingleStore support)

### Step 3: Get Bootstrap Servers

Once cluster is **Active** (15-20 min):

1. Click on your cluster name
2. Click **"View client information"**
3. Copy **"Bootstrap servers"** (TLS endpoints)
   - Example: `b-1.singlestore-hn-kafka.xxxxx.c2.kafka.us-east-1.amazonaws.com:9094,b-2.singlestore-hn-kafka.xxxxx.c2.kafka.us-east-1.amazonaws.com:9094`

### Step 4: Create Kafka Topics

Use AWS CLI or Console:

**Using AWS CLI:**
```bash
# Set your bootstrap servers
BOOTSTRAP_SERVERS="<your-bootstrap-servers-from-step-3>"

# Create topics
aws kafka create-topic \
  --cluster-arn <your-cluster-arn> \
  --topic-name hn-stories \
  --partitions 4 \
  --replication-factor 2

aws kafka create-topic \
  --cluster-arn <your-cluster-arn> \
  --topic-name hn-comments \
  --partitions 4 \
  --replication-factor 2
```

**Or use Console:**
1. MSK → Clusters → Your cluster → **Topics** tab
2. Click **"Create topic"**
3. Name: `hn-stories`, Partitions: `4`, Replication: `2`
4. Repeat for `hn-comments`

### Step 5: Update `.env` File

```bash
# Update these in your .env file:
KAFKA_BOOTSTRAP_SERVERS=b-1.xxxxx.kafka.us-east-1.amazonaws.com:9094,b-2.xxxxx.kafka.us-east-1.amazonaws.com:9094
KAFKA_TOPIC_STORIES=hn-stories
KAFKA_TOPIC_COMMENTS=hn-comments
```

### Step 6: Test Connection from SingleStore

```bash
# Run pipeline setup
./venv/bin/python scripts/setup_pipelines.py
```

If successful, you'll see:
```
✓ Created pipeline: hn_stories_pipeline
✓ Created pipeline: hn_comments_pipeline
✓ All pipelines created successfully!
```

---

## Alternative: MSK Serverless (Easier Setup)

If the above networking is too complex, use **MSK Serverless**:

### Benefits:
- ✅ No broker sizing/management
- ✅ Automatic scaling
- ✅ Public endpoint by default
- ✅ Built-in IAM authentication

### Setup:
1. MSK Console → **Create cluster** → **Serverless**
2. Name: `singlestore-hn-kafka-serverless`
3. **Capacity**: 1 partition per topic
4. **VPC & Subnets**: Default VPC, public subnets
5. **Security**: Create new security group with port 9098 open
6. Create cluster (~5 minutes)

### Configure SingleStore for IAM Auth:

In your pipeline SQL, use:
```sql
CONFIG '{
    "security.protocol": "SASL_SSL",
    "sasl.mechanism": "AWS_MSK_IAM",
    "sasl.jaas.config": "org.apache.kafka.common.security.aws.AwsIamLoginModule required;"
}'
```

---

## Troubleshooting

### Connection Refused
- Check security group allows inbound on 9092/9094
- Verify cluster is in **Active** state
- Ensure SingleStore can reach AWS (test with `telnet`)

### Authentication Failed
- Use unauthenticated access for demo
- Or configure IAM properly with SingleStore

### Topics Not Found
- Create topics manually first
- MSK doesn't auto-create topics by default

### TLS Errors
- Use port 9094 (TLS) not 9092 (plaintext)
- Update pipeline CONFIG with `security.protocol: SASL_SSL`

---

## Cost Optimization

**After Demo:**
```bash
# Delete cluster to avoid charges
aws kafka delete-cluster --cluster-arn <your-cluster-arn>

# Or via Console: MSK → Clusters → Select → Actions → Delete
```

**Estimated Costs:**
- MSK Provisioned (2x t3.small): ~$3-4/day
- MSK Serverless: $0.05/GB ingested + $0.10/GB stored
- Data transfer: First 100GB free/month

---

## Quick Start for Beginners

If you've never used AWS MSK, I recommend:

1. **Start with MSK Serverless** - easier networking
2. **Use AWS Console** - visual interface
3. **Enable CloudWatch** - monitor cluster health
4. **Use IAM authentication** - more secure than unauthenticated

**Next Steps After Setup:**
```bash
# 1. Update .env with MSK bootstrap servers
# 2. Create pipelines
./venv/bin/python scripts/setup_pipelines.py

# 3. Update fetcher to use MSK endpoint
# Edit fetcher/config.py with new KAFKA_BOOTSTRAP_SERVERS

# 4. Start fetcher
docker-compose up -d hn-fetcher

# 5. Monitor pipelines
# SQL: SELECT * FROM information_schema.PIPELINES;
```

---

## Need Help?

- **AWS MSK Docs**: https://docs.aws.amazon.com/msk/
- **SingleStore Pipelines**: https://docs.singlestore.com/cloud/load-data/
- **Contact**: AWS Support or SingleStore Support for connectivity issues
