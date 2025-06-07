#!/bin/bash

#TODO: Privision Redis idempotently with the function deployment

# Configuration
FUNCTION_NAME="architecture-discovery"
PROJECT_ID="${PROJECT_ID:-devops-realm}"
REGION="${REGION:-europe-west4}"
REDIS_HOST="${REDIS_HOST:-your-redis-host}"
REDIS_PASSWORD="${REDIS_PASSWORD:-your-redis-password}"

echo "🚀 Deploying Architecture Discovery Cloud Function..."
echo "   Function Name: $FUNCTION_NAME"
echo "   Project: $PROJECT_ID"
echo "   Region: $REGION"

# Check if gcloud is installed and authenticated
if ! command -v gcloud &> /dev/null; then
    echo "❌ gcloud CLI is not installed. Please install it first."
    echo "   https://cloud.google.com/sdk/docs/install"
    exit 1
fi

# Check if authenticated
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "@"; then
    echo "🔑 Not authenticated with gcloud. Please run: gcloud auth login"
    exit 1
fi

# Set project
gcloud config set project $PROJECT_ID

# Enable required APIs
echo "🔧 Enabling required APIs..."
gcloud services enable cloudfunctions.googleapis.com
gcloud services enable run.googleapis.com
gcloud services enable compute.googleapis.com
gcloud services enable artifactregistry.googleapis.com
gcloud services enable cloudbuild.googleapis.com

# Deploy the function
echo "📦 Deploying Cloud Function..."
gcloud functions deploy $FUNCTION_NAME \
    --gen2 \
    --runtime=python311 \
    --region=$REGION \
    --source=. \
    --entry-point=architecture_discovery \
    --trigger-http \
    --allow-unauthenticated \
    --memory=512MB \
    --timeout=60s \
    --max-instances=10 \
    --min-instances=0 \
    --set-env-vars="PROJECT_ID=$PROJECT_ID,REGION=$REGION,REDIS_HOST=$REDIS_HOST,REDIS_PASSWORD=$REDIS_PASSWORD,CACHE_TTL=300" \
    --project=$PROJECT_ID

if [ $? -eq 0 ]; then
    echo "✅ Deployment completed successfully!"
    
    # Get function URL
    FUNCTION_URL=$(gcloud functions describe $FUNCTION_NAME \
        --region=$REGION \
        --project=$PROJECT_ID \
        --format="value(serviceConfig.uri)")
    
    echo ""
    echo "🌐 Function URLs:"
    echo "   Main endpoint: $FUNCTION_URL"
    echo "   Health check: $FUNCTION_URL/health"
    echo "   Summary: $FUNCTION_URL?format=summary"
    echo "   Fresh data: $FUNCTION_URL?refresh=true"
    echo ""
    echo "📋 Test the function:"
    echo "   curl \"$FUNCTION_URL\""
    echo "   curl \"$FUNCTION_URL?format=summary\""
else
    echo "❌ Deployment failed!"
    exit 1
fi