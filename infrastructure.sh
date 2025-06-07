#!/bin/bash

# ! --- Configuration Variables Left Here for Clarity --- !
export PROJECT_ID="devops-realm"
export PROJECT_NAME="zetta-challenge-prod"
export DOCKER_REGISTRY_NAME="$PROJECT_NAME-registry"
export REGION="europe-west4"

export BE_API_SERVICE_NAME="be-api-service-prod"
export BE_API_IMAGE="$REGION-docker.pkg.dev/$PROJECT_ID/$DOCKER_REGISTRY_NAME/$BE_API_SERVICE_NAME"

export FE_SVELTE_SERVICE_NAME="fe-svelte-app-prod"
export FE_SVELTE_IMAGE="$REGION-docker.pkg.dev/$PROJECT_ID/$DOCKER_REGISTRY_NAME/$FE_SVELTE_SERVICE_NAME"

export VPC_NETWORK="$PROJECT_NAME-vpc-euwest4"
export SUBNET_NAME="$PROJECT_NAME-subnet-euwest4"
export SUBNET_IP_CIDR="192.168.0.0/24"

# ! --- Docker Registry --- !
# TODO: Try a more explicit approach, not relying on list count
#? Prone to False Positives
echo "Checking if repository exists..."
REGISTRY_EXISTS=$(gcloud artifacts repositories list \
--location="$REGION" \
--format="value(name)" | grep -c "${DOCKER_REGISTRY_NAME}$")

if [[ "$REGISTRY_EXISTS" == "0" ]]; then
echo "Creating Docker repository..."
gcloud artifacts repositories create $DOCKER_REGISTRY_NAME \
    --repository-format=docker \
    --location="$REGION" \
    --description="Docker repository for zetta challenge"
else
echo "Repository '$DOCKER_REGISTRY_NAME' already exists."
fi
# ! --- Docker Registry --- !

# ! --- VPC & Subnet --- !
if ! gcloud compute networks describe $VPC_NETWORK --project=$PROJECT_ID &> /dev/null; then
    echo "VPC network '$VPC_NETWORK' not found. Creating it..."
    gcloud compute networks create $VPC_NETWORK \
        --subnet-mode=custom \
        --bgp-routing-mode=regional \
        --project=$PROJECT_ID || { echo "Failed to create VPC network."; exit 1; }
    echo "VPC network '$VPC_NETWORK' created successfully."
else
    echo "VPC network '$VPC_NETWORK' already exists."
fi
if ! gcloud compute networks subnets describe $SUBNET_NAME --region=$REGION --project=$PROJECT_ID &> /dev/null; then
    echo "Subnet '$SUBNET_NAME' not found in region '$REGION'. Creating it..."
    gcloud compute networks subnets create $SUBNET_NAME \
        --network=$VPC_NETWORK \
        --range=$SUBNET_IP_CIDR \
        --region=$REGION \
        --enable-private-ip-google-access \
        --project=$PROJECT_ID || { echo "Failed to create subnet."; exit 1; }
    echo "Subnet '$SUBNET_NAME' created successfully with CIDR '$SUBNET_IP_CIDR'."
else
    echo "Subnet '$SUBNET_NAME' already exists in region '$REGION'."
    EXISTING_CIDR=$(gcloud compute networks subnets describe $SUBNET_NAME --region=$REGION --project=$PROJECT_ID --format="value(ipCidrRange)")
    if [ "$EXISTING_CIDR" != "$SUBNET_IP_CIDR" ]; then
        echo "Warning: Existing subnet CIDR '$EXISTING_CIDR' differs from expected '$SUBNET_IP_CIDR'."
        echo "Using existing subnet configuration."
        export SUBNET_IP_CIDR=$EXISTING_CIDR
    fi
fi

# ! --- Docker Build & Push --- !
build_and_push_image() {
    local service_name="$1"
    local docker_dir="$2"
    local image_name="$REGION-docker.pkg.dev/$PROJECT_ID/$DOCKER_REGISTRY_NAME/$service_name"

    echo "🚀 Building Image for: $service_name"
    echo "   Project: $PROJECT_ID"
    echo "   Region: $REGION"
    echo "   Registry: $REGISTRY_NAME"
    echo "   Docker Image: $image_name"

    if ! command -v gcloud &> /dev/null; then
        echo "❌ gcloud CLI is not installed. Please install it first."
        echo "   https://cloud.google.com/sdk/docs/install"
        return 1
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
    # TODO: BEWARE -> Relative paths are a nightmare I know...
    cd ../$docker_dir
    docker build --platform linux/amd64 -t $image_name .

    echo "🔐 Setting up Docker authentication to GCP..."
    gcloud auth configure-docker $REGION-docker.pkg.dev

    echo "📤 Pushing image to Google Container Registry..."
    docker push $image_name

    echo "✅ Image Update completed!"
}

echo "Building and Pushing Docker Images..."
if build_and_push_image $BE_API_SERVICE_NAME "backend"; then
    echo "✓ Backend API Image pushed successfully"
else
    echo "✗ Backend API Service Registry push failed"
    exit 1
fi

if build_and_push_image $FE_SVELTE_SERVICE_NAME "frontend"; then
    echo "✓ Frontend Service Image pushed successfully"
else
    echo "✗ Frontend Service Registry push failed"
    exit 1
fi
echo "Cloud Run services deployment commands issued."

# TODO: BEWARE -> Relative paths are a nightmare I know...
cd ../infrastructure

check_image_exists() {
    local image_name=$1
    local service_name=$2
    
    echo "Checking if image exists: $image_name"
    if ! gcloud container images describe $image_name --project=$PROJECT_ID &> /dev/null; then
        echo "Warning: Container image '$image_name' for service '$service_name' not found."
        echo "Please ensure the image is built and pushed to the registry before running this script."
        echo "Skipping deployment of $service_name..."
        return 1
    fi
    echo "✓ Image verified: $image_name"
    return 0
}

# ! --- Cloud Run Deployment --- !
#TODO: Add a dedicated IAM service account for each crun instance
#TODO: Optimize the code duplication within the function, kinda pointless right now -> CICD First
#TODO: Interpolate the image name within the function and reduce variable clutter on top
deploy_cloud_run_service() {
    local service_name=$1
    local image_name=$2
    local ingress_setting=$3
    local vpc_egress_setting=$4
    local network=$5
    local subnet=$6

    echo "Deploying/Updating Cloud Run service: $service_name"

    if ! check_image_exists "$image_name" "$service_name"; then
        return 1
    fi

    if ! gcloud run services describe $service_name --platform managed --region $REGION --project $PROJECT_ID &> /dev/null; then
        echo "Service '$service_name' not found. Creating..."
        gcloud run deploy $service_name \
            --image $image_name \
            --platform managed \
            --region $REGION \
            --allow-unauthenticated \
            --ingress $ingress_setting \
            --network=$network \
            --subnet=$subnet \
            --vpc-egress=$vpc_egress_setting \
            --project $PROJECT_ID \
            --env-vars-file ./.env.$service_name.yaml || { echo "Failed to deploy $service_name."; return 1; }
            
    else
        echo "Service '$service_name' already exists. Updating the networking..."
        gcloud run services update $service_name \
            --image $image_name \
            --platform managed \
            --region $REGION \
            --ingress $ingress_setting \
            --network=$network \
            --subnet=$subnet \
            --vpc-egress=$vpc_egress_setting \
            --project $PROJECT_ID \
            --env-vars-file ./.env.$service_name.yaml || { echo "Failed to deploy $service_name."; return 1; }
    fi

    echo "Service $service_name deployment initiated."
}

echo "Deploying Cloud Run services..."
# deploy_cloud_run_service $BE_API_SERVICE_NAME $BE_API_IMAGE "internal" "all-traffic" $VPC_NETWORK $SUBNET_NAME || exit 1
if deploy_cloud_run_service $BE_API_SERVICE_NAME $BE_API_IMAGE "all" "private-ranges-only" $VPC_NETWORK $SUBNET_NAME; then
    echo "✓ Backend API Service deployment completed successfully"
else
    echo "✗ Backend API Service deployment failed"
    exit 1
fi

# deploy_cloud_run_service $FE_SVELTE_SERVICE_NAME $FE_SVELTE_IMAGE "all" "all-traffic" $VPC_NETWORK $SUBNET_NAME || exit 1
if deploy_cloud_run_service $FE_SVELTE_SERVICE_NAME $FE_SVELTE_IMAGE "all" "all-traffic" $VPC_NETWORK $SUBNET_NAME; then
    echo "✓ Frontend Service deployment completed successfully"
else
    echo "✗ Frontend Service deployment failed"
    exit 1
fi
echo "Cloud Run services deployment commands issued."