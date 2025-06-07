#!/bin/bash

# GCP Infrastructure Cleanup Script
# This script assumingly deletes resources in the correct dependency order
# TODO: Needs more testing with reprovisioning the infra

# ! --- Configuration Variables (Match your main script) --- !
export PROJECT_ID="devops-realm"
export PROJECT_NAME="zetta-challenge-prod"
export REGION="europe-west4"

export BE_API_SERVICE_NAME="be-api-service-prod"
export FE_SVELTE_SERVICE_NAME="fe-svelte-app-prod"

export VPC_NETWORK="$PROJECT_NAME-vpc-euwest4"
export SUBNET_NAME="$PROJECT_NAME-subnet-euwest4"
export PROXY_ONLY_SUBNET_NAME="$PROJECT_NAME-proxy-subnet-euwest4"

export BE_API_SERVICE_NEG_NAME="neg-$BE_API_SERVICE_NAME"
export BE_API_SERVICE_LB_LINK="$BE_API_SERVICE_NAME-lb-link"
export URL_MAP_NAME="internal-api-url-map-$PROJECT_NAME"
export PROXY_NAME="internal-api-proxy-$PROJECT_NAME"
export FORWARDING_RULE_NAME="internal-api-forwarding-rule-$PROJECT_NAME"
export INTERNAL_ALB_IP_ADDRESS_NAME="internal-alb-ip-$PROJECT_NAME"
export SSL_CERT_NAME="internal-api-ssl-cert-$PROJECT_NAME"

export MANAGED_ZONE_NAME="internal-api-zone-$PROJECT_NAME"
export DNS_SUFFIX="internal.$PROJECT_NAME.com"
export INTERNAL_HOSTNAME="api.$DNS_SUFFIX"

export INTERNAL_FIREWALL_RULE="allow-internal-$VPC_NETWORK"
export LB_HEALTH_CHECK_FIREWALL_RULE="allow-lb-health-checks-$VPC_NETWORK"
export INTERNAL_LB_FIREWALL_RULE="allow-internal-lb-$VPC_NETWORK"

echo "⚠️  WARNING: This will delete ALL infrastructure resources!"
echo "Project: $PROJECT_ID"
echo "Region: $REGION"
echo ""
read -p "Are you sure you want to continue? (yes/no): " confirm

if [[ $confirm != "yes" ]]; then
    echo "Cleanup cancelled."
    exit 0
fi

echo "Setting project to $PROJECT_ID..."
gcloud config set project $PROJECT_ID

echo ""
echo "🗑️  Starting cleanup in dependency order..."

# 1. Delete DNS Records first
echo "Deleting DNS A record..."
if gcloud dns record-sets describe "$INTERNAL_HOSTNAME." --type="A" --zone=$MANAGED_ZONE_NAME --project=$PROJECT_ID &> /dev/null; then
    gcloud dns record-sets delete "$INTERNAL_HOSTNAME." \
        --type="A" \
        --zone=$MANAGED_ZONE_NAME \
        --project=$PROJECT_ID -q || echo "Failed to delete A record"
else
    echo "DNS A record does not exist"
fi

# 2. Delete DNS Managed Zone
echo "Deleting DNS managed zone..."
if gcloud dns managed-zones describe $MANAGED_ZONE_NAME --project=$PROJECT_ID &> /dev/null; then
    gcloud dns managed-zones delete $MANAGED_ZONE_NAME \
        --project=$PROJECT_ID -q || echo "Failed to delete DNS zone"
else
    echo "DNS managed zone does not exist"
fi

# 3. Delete Forwarding Rule
echo "Deleting forwarding rule..."
if gcloud compute forwarding-rules describe $FORWARDING_RULE_NAME --region=$REGION --project=$PROJECT_ID &> /dev/null; then
    gcloud compute forwarding-rules delete $FORWARDING_RULE_NAME \
        --region=$REGION \
        --project=$PROJECT_ID -q || echo "Failed to delete forwarding rule"
else
    echo "Forwarding rule does not exist"
fi

# 4. Delete HTTPS Proxy (or HTTP Proxy if exists)
echo "Deleting HTTPS proxy..."
if gcloud compute target-https-proxies describe $PROXY_NAME --region=$REGION --project=$PROJECT_ID &> /dev/null; then
    gcloud compute target-https-proxies delete $PROXY_NAME \
        --region=$REGION \
        --project=$PROJECT_ID -q || echo "Failed to delete HTTPS proxy"
else
    echo "HTTPS proxy does not exist"
fi

echo "Checking for HTTP proxy..."
if gcloud compute target-http-proxies describe $PROXY_NAME --region=$REGION --project=$PROJECT_ID &> /dev/null; then
    gcloud compute target-http-proxies delete $PROXY_NAME \
        --region=$REGION \
        --project=$PROJECT_ID -q || echo "Failed to delete HTTP proxy"
else
    echo "HTTP proxy does not exist"
fi

# 5. Delete SSL Certificate
echo "Deleting SSL certificate..."
if gcloud compute ssl-certificates describe $SSL_CERT_NAME --region=$REGION --project=$PROJECT_ID &> /dev/null; then
    gcloud compute ssl-certificates delete $SSL_CERT_NAME \
        --region=$REGION \
        --project=$PROJECT_ID -q || echo "Failed to delete SSL certificate"
else
    echo "SSL certificate does not exist"
fi

# 6. Delete URL Map
echo "Deleting URL map..."
if gcloud compute url-maps describe $URL_MAP_NAME --region=$REGION --project=$PROJECT_ID &> /dev/null; then
    gcloud compute url-maps delete $URL_MAP_NAME \
        --region=$REGION \
        --project=$PROJECT_ID -q || echo "Failed to delete URL map"
else
    echo "URL map does not exist"
fi

# 7. Delete Backend Service
echo "Deleting backend service..."
if gcloud compute backend-services describe $BE_API_SERVICE_LB_LINK --region=$REGION --project=$PROJECT_ID &> /dev/null; then
    gcloud compute backend-services delete $BE_API_SERVICE_LB_LINK \
        --region=$REGION \
        --project=$PROJECT_ID -q || echo "Failed to delete backend service"
else
    echo "Backend service does not exist"
fi

# 8. Delete Network Endpoint Group
echo "Deleting network endpoint group..."
if gcloud compute network-endpoint-groups describe $BE_API_SERVICE_NEG_NAME --region=$REGION --project=$PROJECT_ID &> /dev/null; then
    gcloud compute network-endpoint-groups delete $BE_API_SERVICE_NEG_NAME \
        --region=$REGION \
        --project=$PROJECT_ID -q || echo "Failed to delete NEG"
else
    echo "Network endpoint group does not exist"
fi

# 9. Delete Static IP Address
echo "Deleting static IP address..."
if gcloud compute addresses describe $INTERNAL_ALB_IP_ADDRESS_NAME --region=$REGION --project=$PROJECT_ID &> /dev/null; then
    gcloud compute addresses delete $INTERNAL_ALB_IP_ADDRESS_NAME \
        --region=$REGION \
        --project=$PROJECT_ID -q || echo "Failed to delete static IP"
else
    echo "Static IP address does not exist"
fi

# 10. Delete Firewall Rules
echo "Deleting firewall rules..."
if gcloud compute firewall-rules describe $INTERNAL_FIREWALL_RULE --project=$PROJECT_ID &> /dev/null; then
    gcloud compute firewall-rules delete $INTERNAL_FIREWALL_RULE \
        --project=$PROJECT_ID -q || echo "Failed to delete internal firewall rule"
else
    echo "Internal firewall rule does not exist"
fi

if gcloud compute firewall-rules describe $LB_HEALTH_CHECK_FIREWALL_RULE --project=$PROJECT_ID &> /dev/null; then
    gcloud compute firewall-rules delete $LB_HEALTH_CHECK_FIREWALL_RULE \
        --project=$PROJECT_ID -q || echo "Failed to delete LB health check firewall rule"
else
    echo "LB health check firewall rule does not exist"
fi

if gcloud compute firewall-rules describe $INTERNAL_LB_FIREWALL_RULE --project=$PROJECT_ID &> /dev/null; then
    gcloud compute firewall-rules delete $INTERNAL_LB_FIREWALL_RULE \
        --project=$PROJECT_ID -q || echo "Failed to delete internal LB firewall rule"
else
    echo "Internal LB firewall rule does not exist"
fi

# 11. Delete Subnets
echo "Deleting proxy-only subnet..."
if gcloud compute networks subnets describe $PROXY_ONLY_SUBNET_NAME --region=$REGION --project=$PROJECT_ID &> /dev/null; then
    gcloud compute networks subnets delete $PROXY_ONLY_SUBNET_NAME \
        --region=$REGION \
        --project=$PROJECT_ID -q || echo "Failed to delete proxy-only subnet"
else
    echo "Proxy-only subnet does not exist"
fi

echo "Deleting main subnet..."
if gcloud compute networks subnets describe $SUBNET_NAME --region=$REGION --project=$PROJECT_ID &> /dev/null; then
    gcloud compute networks subnets delete $SUBNET_NAME \
        --region=$REGION \
        --project=$PROJECT_ID -q || echo "Failed to delete main subnet"
else
    echo "Main subnet does not exist"
fi

# 12. Delete VPC Network (last)
echo "Deleting VPC network..."
if gcloud compute networks describe $VPC_NETWORK --project=$PROJECT_ID &> /dev/null; then
    gcloud compute networks delete $VPC_NETWORK \
        --project=$PROJECT_ID -q || echo "Failed to delete VPC network"
else
    echo "VPC network does not exist"
fi

echo ""
echo "🎯 Cleanup completed!"
echo ""
echo "Note: Cloud Run services and Docker registry were NOT deleted."
echo "To delete them manually if needed:"
echo "  gcloud run services delete $FE_SVELTE_SERVICE_NAME --region=$REGION --project=$PROJECT_ID"
echo "  gcloud run services delete $BE_API_SERVICE_NAME --region=$REGION --project=$PROJECT_ID"
echo "  gcloud artifacts repositories delete $DOCKER_REGISTRY_NAME --location=$REGION --project=$PROJECT_ID"