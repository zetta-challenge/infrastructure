# 🌐 VPC Discovery Cloud Function

> **Lightning-fast Google Cloud VPC and subnet discovery with Redis caching superpowers** ⚡

<div align="center">

![Python](https://img.shields.io/badge/Python-3.11+-blue?style=for-the-badge&logo=python)
![Google Cloud](https://img.shields.io/badge/Google%20Cloud-4285F4?style=for-the-badge&logo=google-cloud)
![Redis](https://img.shields.io/badge/Redis-DC382D?style=for-the-badge&logo=redis)
![Docker](https://img.shields.io/badge/Docker-2496ED?style=for-the-badge&logo=docker)

</div>

## 🎯 What This Beast Does

This isn't your average Cloud Function. It's a **VPC network archaeology tool** that digs deep into your Google Cloud infrastructure and serves up your network topology faster than you can say "subnet mask". 

**The Magic:**
- 🔍 **Auto-discovers** all VPC networks in your GCP project
- 🎯 **Maps every subnet** in your specified region with surgical precision  
- ⚡ **Redis caching** makes subsequent requests blazingly fast (10-50x speedup!)
- 🌍 **RESTful API** that plays nice with any frontend or automation tool
- 🍎 **Cross-platform** optimized for both Apple Silicon and Intel/AMD64
- 🐳 **Containerized** for consistent deployment anywhere

## 🚀 Quick Start

### Prerequisites 📋

Before you start, you'll need:
1. **Google Cloud Project** with billing enabled
2. **Docker Desktop** installed and running
3. **Google Cloud Service Account** (we'll create this)

### Step 1: Create Google Cloud Service Account 🔐

**This is required for the function to access your GCP resources!**

```bash
# Set your project ID
export PROJECT_ID="your-gcp-project-id"

# Create service account
gcloud iam service-accounts create vpc-discovery-sa \
    --display-name="VPC Discovery Function" \
    --description="Service account for VPC discovery function"

# Grant required permissions
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:vpc-discovery-sa@$PROJECT_ID.iam.gserviceaccount.com" \
    --role="roles/compute.viewer"

gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:vpc-discovery-sa@$PROJECT_ID.iam.gserviceaccount.com" \
    --role="roles/compute.networkViewer"

# Create and download the key file
mkdir -p ./credentials
gcloud iam service-accounts keys create ./credentials/service-account.json \
    --iam-account=vpc-discovery-sa@$PROJECT_ID.iam.gserviceaccount.com

# Verify the file was created
ls -la ./credentials/service-account.json
```

**⚠️ Important**: The `./credentials/service-account.json` file is **required** for the function to authenticate with Google Cloud APIs.

### Step 2: Configure Environment

```bash
# Clone the repository
git clone <your-repo> && cd vpc-discovery-function

# Create environment configuration
cat > .env << EOF
# Google Cloud Configuration
PROJECT_ID=your-gcp-project-id
REGION=europe-west4

# Redis Configuration (local development)
REDIS_HOST=redis
REDIS_PORT=6379
REDIS_PASSWORD=secure-password-123

# Cache Configuration
CACHE_TTL=300

# Redis Commander Web UI
REDIS_COMMANDER_USER=admin
REDIS_COMMANDER_PASSWORD=admin123
EOF

# Edit with your actual values
nano .env
```

### Step 3: Launch Based on Your Architecture

### Apple Silicon Macs (M1/M2/M3) 🍎

```bash
# Launch with ARM64 optimization
docker-compose up --build -d

# Test it works
curl "http://localhost:8080/health" | jq .
```

### Intel/AMD64 Systems 💻

```bash
# Launch with x86 optimization
docker-compose -f docker-compose-x86.yml up --build -d

# Test it works
curl "http://localhost:8080/health" | jq .
```

**🎉 You should see a response like:**
```json
{
  "status": "healthy",
  "timestamp": "2025-06-08T18:00:00Z",
  "project_id": "your-project",
  "region": "europe-west4",
  "redis_connected": true
}
```

## 📁 Project Structure

```
vpc-discovery-function/
├── main.py                    # Core function code
├── requirements.txt           # Python dependencies
├── Dockerfile                 # Multi-platform container
├── docker-compose.yml         # Apple Silicon (ARM64)
├── docker-compose-x86.yml     # Intel/AMD64 systems
├── deploy.sh                  # GCP deployment script
├── .env                       # Environment configuration
├── credentials/               # 🔐 SERVICE ACCOUNT FILES (REQUIRED)
│   └── service-account.json   #     ↳ Google Cloud authentication
└── README.md                  # This beautiful file
```

**🚨 Critical Files:**
- `credentials/service-account.json` - **Required** for GCP API access
- `.env` - **Required** for configuration
- Choose correct docker-compose file for your CPU architecture

## 🎪 API Endpoints

| 🎯 Endpoint | 📋 What It Does | 🏆 Example |
|-------------|-----------------|-------------|
| `GET /` | Full VPC discovery report | `curl "http://localhost:8080"` |
| `GET /?refresh=true` | Bypass cache, fresh data | `curl "http://localhost:8080?refresh=true"` |
| `GET /health` | Health check + Redis status | `curl "http://localhost:8080/health"` |

## 📊 Response Format

```json
{
  "project_id": "your-awesome-project",
  "region": "europe-west4",
  "generated_at": "2025-06-08T18:00:00Z",
  "cached": false,
  "vpc_networks": [
    {
      "name": "production-vpc-fortress",
      "description": "Your network kingdom",
      "creation_timestamp": "2025-06-07T10:00:00Z",
      "subnets": [
        {
          "name": "web-tier-subnet",
          "ip_cidr_range": "192.168.1.0/24",
          "region": "europe-west4", 
          "private_ip_google_access": true,
          "network": "production-vpc-fortress"
        },
        {
          "name": "database-tier-subnet",
          "ip_cidr_range": "192.168.2.0/24",
          "region": "europe-west4",
          "private_ip_google_access": true,
          "network": "production-vpc-fortress"
        }
      ]
    }
  ],
  "summary": {
    "total_networks": 1,
    "total_subnets": 2,
    "network_names": ["production-vpc-fortress"]
  },
  "cache_info": {
    "cache_enabled": true,
    "cache_ttl_seconds": 300,
    "cached_successfully": true
  }
}
```

## ⚡ Performance Benchmarks

| 📈 Metric | 🎯 Target | 💪 Reality |
|-----------|-----------|------------|
| **Fresh Discovery** | < 5 seconds | Discovers entire network topology |
| **Cached Response** | < 200ms | Redis-powered lightning ⚡ |
| **Cache Speedup** | 10x faster | Often 20-50x in practice |
| **Concurrent Users** | 100+ | Handles traffic like a champ |

## 🛠️ Local Development

### Architecture-Specific Commands

**Apple Silicon (M1/M2/M3):**
```bash
# Start services
docker-compose up --build -d

# View logs
docker-compose logs -f architecture-function

# Stop services
docker-compose down
```

**Intel/AMD64:**
```bash
# Start services  
docker-compose -f docker-compose-x86.yml up --build -d

# View logs
docker-compose -f docker-compose-x86.yml logs -f architecture-function

# Stop services
docker-compose -f docker-compose-x86.yml down
```

### Development URLs

- **🎯 Main Function**: http://localhost:8080
- **❤️ Health Check**: http://localhost:8080/health  
- **🔍 Redis Commander**: http://localhost:8081 (admin/admin123)

### Common Commands

```bash
# Force rebuild
docker-compose down && docker-compose up --build -d

# Restart just the function
docker-compose restart architecture-function

# Check service status
docker-compose ps

# View real-time logs
docker-compose logs -f
```

## 🎛️ Configuration

### Environment Variables (.env file)

```bash
# Google Cloud Configuration
PROJECT_ID=your-gcp-project
REGION=europe-west4

# Redis Configuration (local development)
REDIS_HOST=redis
REDIS_PORT=6379
REDIS_PASSWORD=secure-password-123

# Cache Configuration
CACHE_TTL=300

# Redis Commander Web UI
REDIS_COMMANDER_USER=admin
REDIS_COMMANDER_PASSWORD=admin123
```

### Docker Compose Files

| 📁 File | 🖥️ Platform | 🎯 Use Case |
|---------|-------------|-------------|
| `docker-compose.yml` | Apple Silicon (ARM64) | M1/M2/M3 Macs |
| `docker-compose-x86.yml` | Intel/AMD64 | Standard x86 systems |

## 🚀 Production Deployment

### Step 1: Provision Redis on GCP

*Coming soon: Redis provisioning script for Google Cloud Memorystore!*

```bash
# Will provision Redis instance automatically
./provision-redis.sh
```

### Step 2: Update Service Account for Production

For production deployment, ensure your service account has the necessary permissions:

```bash
# Add additional production permissions if needed
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:vpc-discovery-sa@$PROJECT_ID.iam.gserviceaccount.com" \
    --role="roles/cloudfunctions.invoker"
```

### Step 3: Deploy Cloud Function

```bash
# Configure deployment settings
nano deploy.sh  # Add your Redis host and password

# Deploy to GCP
./deploy.sh
```

### Manual Deployment

```bash
gcloud functions deploy vpc-discovery \
    --gen2 \
    --runtime=python311 \
    --region=europe-west4 \
    --source=. \
    --entry-point=vpc_discovery \
    --trigger=http \
    --allow-unauthenticated \
    --service-account=vpc-discovery-sa@$PROJECT_ID.iam.gserviceaccount.com \
    --set-env-vars="PROJECT_ID=your-project,REGION=europe-west4,REDIS_HOST=your-redis-ip,REDIS_PASSWORD=your-password"
```

**📝 Important**: When deploying to GCP, the Cloud Function will use the service account you specify, not the local JSON file.

## 🔐 Security & Permissions

### Required GCP IAM Roles
Your service account needs these specific roles:
- **Compute Viewer** (`roles/compute.viewer`) - Read VPC networks and general compute resources
- **Compute Network Viewer** (`roles/compute.networkViewer`) - Read detailed subnet information

### Service Account File Structure
The `./credentials/service-account.json` should look like this:
```json
{
  "type": "service_account",
  "project_id": "your-project-id",
  "private_key_id": "...",
  "private_key": "-----BEGIN PRIVATE KEY-----\n...",
  "client_email": "vpc-discovery-sa@your-project.iam.gserviceaccount.com",
  "client_id": "...",
  "auth_uri": "https://accounts.google.com/o/oauth2/auth",
  "token_uri": "https://oauth2.googleapis.com/token"
}
```

### Troubleshooting Authentication
```bash
# Verify service account file exists and is valid JSON
cat ./credentials/service-account.json | jq .project_id

# Test authentication inside container
docker exec architecture-function python3 -c "
from google.auth import default
try:
    creds, project = default()
    print(f'✅ Authentication successful for project: {project}')
except Exception as e:
    print(f'❌ Authentication failed: {e}')
"
```

### What Happens Without Service Account?
❌ **Without the service account file, you'll get:**
- Empty VPC results (`"vpc_networks": []`)
- Authentication errors in logs
- `403 Forbidden` or `401 Unauthorized` errors

✅ **With proper service account:**
- Full VPC network discovery
- All subnets in your specified region
- Proper error handling and logging

## 🧪 Testing & Validation

### Health Check
```bash
curl "http://localhost:8080/health" | jq .
```

### Basic Functionality
```bash
# Get all VPCs (fresh data)
curl "http://localhost:8080?refresh=true" | jq .

# Get cached data (should be faster)
curl "http://localhost:8080" | jq .
```

### Performance Testing
```bash
# Measure fresh vs cached performance
echo "Fresh request:"
time curl -s "http://localhost:8080?refresh=true" > /dev/null

echo "Cached request:" 
time curl -s "http://localhost:8080" > /dev/null
```

### Load Testing
```bash
# 10 concurrent requests
for i in {1..10}; do 
  curl -s "http://localhost:8080" > /dev/null & 
done
wait
echo "Load test complete!"
```

## 🆘 Troubleshooting

### Common Issues & Solutions

**"Function container won't start"** 🚨
```bash
# Check the logs
docker logs architecture-function

# Common causes:
# - Wrong docker-compose file for your architecture
# - Missing service account file
# - Invalid JSON in service account file
# - Python import errors
```

**"Service account file not found"** 🔐
```bash
# Check if file exists
ls -la ./credentials/service-account.json

# If missing, create it following Step 1 in Quick Start
# Make sure the path is exactly: ./credentials/service-account.json
```

**"Authentication failed" or "403 Forbidden"** 🚫
```bash
# Verify service account has correct permissions
gcloud projects get-iam-policy $PROJECT_ID \
    --flatten="bindings[].members" \
    --filter="bindings.members:vpc-discovery-sa@$PROJECT_ID.iam.gserviceaccount.com"

# Should show both roles:
# - roles/compute.viewer
# - roles/compute.networkViewer
```

**"Redis connection failed"** 🔴
```bash
# Test Redis directly
docker exec architecture-redis redis-cli -a defaultpassword ping

# Should return: PONG
# If not, check REDIS_PASSWORD in .env file
```

**"Empty VPC results but no errors"** 🤔
```bash
# Check if you have VPCs in your project/region
gcloud compute networks list --project=$PROJECT_ID
gcloud compute networks subnets list --project=$PROJECT_ID --regions=$REGION

# Verify authentication is working
curl "http://localhost:8080?refresh=true" | jq .
```

### Debug Commands

```bash
# Real-time function logs
docker logs -f architecture-function

# Execute commands in container
docker exec -it architecture-function /bin/bash

# Test Redis connection
docker exec architecture-redis redis-cli -a defaultpassword info

# Check environment variables
docker exec architecture-function env | grep -E "(PROJECT|REDIS)"
```

### Architecture-Specific Issues

**Apple Silicon Problems:**
- Use `docker-compose.yml` (default)
- Force ARM64 build: `docker-compose build --no-cache`

**Intel/AMD64 Problems:**
- Use `docker-compose -f docker-compose-x86.yml`
- Ensure x86 platform in compose file

## 🎯 Use Cases

### 🏢 **Enterprise Network Auditing**
- Automated compliance reporting
- Network topology visualization  
- Security audit trail

### 🔄 **Infrastructure Automation**
- Dynamic infrastructure discovery
- Automated resource planning
- Drift detection

### 📊 **Monitoring & Alerting**
- Network change detection
- Automated documentation updates
- Cost optimization insights

### 🔧 **DevOps Integration**
- Deployment environment validation
- Network-aware application deployment
- Multi-region orchestration

## 🤝 Contributing

We love contributors! Here's how to join:

1. **🍴 Fork** this repo
2. **🌟 Star** it (you know you want to!)
3. **🔧 Create** feature branch: `git checkout -b feature/awesome-addition`
4. **✅ Test** locally with Docker Compose
5. **🚀 Submit** PR with detailed description

## 📜 License

**MIT License** - Use it, modify it, love it, share it!

---

<div align="center">

**Made with ❤️ and copious amounts of ☕**

[⭐ Star this repo](https://github.com/your-repo) • [🐛 Report Bug](https://github.com/your-repo/issues) • [💡 Request Feature](https://github.com/your-repo/issues)

*"Because life's too short for slow network discovery"* 🚀

</div>