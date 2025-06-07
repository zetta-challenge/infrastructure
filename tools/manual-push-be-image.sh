#!/bin/bash
set -e

# ! For a manual run -> Paste the contents of the script below in the root directory of the BE project
# ! --- Configuration Variables Left Here for Clarity --- !
SERVICE_NAME="be-api-service-prod"
PROJECT_ID="devops-realm"
PROJECT_NAME="zetta-challenge-prod"
REGISTRY_NAME="$PROJECT_NAME-registry"
REGION="europe-west4"
IMAGE_NAME="$REGION-docker.pkg.dev/$PROJECT_ID/$REGISTRY_NAME/$SERVICE_NAME"

echo "🚀 Building Image for: $SERVICE_NAME"
echo "   Project: $PROJECT_ID"
echo "   Region: $REGION"
echo "   Registry: $REGISTRY_NAME"
echo "   Docker Image: $IMAGE_NAME"

if ! command -v gcloud &> /dev/null; then
    echo "❌ gcloud CLI is not installed. Please install it first."
    echo "   https://cloud.google.com/sdk/docs/install"
    exit 1
fi

echo "🔑 Authenticating with Google Cloud..."
if gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "@"; then
    echo "Already authenticated, skipping login"
  else
    gcloud auth login
  fi
gcloud config set project $PROJECT_ID
gcloud config set compute/region $REGION

echo "🔨 Building Docker image..."
docker build --platform linux/amd64 -t $IMAGE_NAME .

echo "🔐 Setting up Docker authentication to GCP..."
gcloud auth configure-docker $REGION-docker.pkg.dev

echo "📤 Pushing image to Google Container Registry..."
docker push $IMAGE_NAME

echo "✅ Image Update completed!"