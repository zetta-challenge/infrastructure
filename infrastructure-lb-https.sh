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
export PROXY_ONLY_SUBNET_NAME="$PROJECT_NAME-proxy-subnet-euwest4"
export PROXY_ONLY_SUBNET_CIDR="192.168.100.0/24"

export BE_API_SERVICE_NEG_NAME="neg-$BE_API_SERVICE_NAME"
export BE_API_SERVICE_LB_LINK="$BE_API_SERVICE_NAME-lb-link"
export URL_MAP_NAME="internal-api-url-map-$PROJECT_NAME"
export PROXY_NAME="internal-api-proxy-$PROJECT_NAME"
export FORWARDING_RULE_NAME="internal-api-forwarding-rule-$PROJECT_NAME"
export INTERNAL_ALB_IP_ADDRESS_NAME="internal-alb-ip-$PROJECT_NAME"
export IP_TO_ASSIGN="192.168.0.10"
export SSL_CERT_NAME="internal-api-ssl-cert-$PROJECT_NAME"

export MANAGED_ZONE_NAME="internal-api-zone-$PROJECT_NAME"
export DNS_SUFFIX="internal.$PROJECT_NAME.com"
export INTERNAL_HOSTNAME="api.$DNS_SUFFIX"

export REQUIRED_APIS=(
    "iam.googleapis.com"
    "compute.googleapis.com"
    "run.googleapis.com"
    "dns.googleapis.com"
    "artifactregistry.googleapis.com"
    "logging.googleapis.com"
    "monitoring.googleapis.com"
    "cloudresourcemanager.googleapis.com"
)
# # ! --- Configuration Variables --- !

echo "Setting project to $PROJECT_ID..."
gcloud config set project $PROJECT_ID

echo "Enabling APIs for project: $PROJECT_ID"
echo "Checking current API status..."
ENABLED_APIS=$(gcloud services list --enabled --format="value(name)" --project="$PROJECT_ID")

APIS_TO_ENABLE=()
for api in "${REQUIRED_APIS[@]}"; do
    if gcloud services list --enabled --filter="name:$api" --format="value(name)" --project="$PROJECT_ID" | grep -q "$api"; then
        echo "✓ $api (already enabled)"
    else
        echo "○ $api (needs enabling)"
        APIS_TO_ENABLE+=("$api")
    fi
done

if [ ${#APIS_TO_ENABLE[@]} -gt 0 ]; then
    echo ""
    echo "Enabling ${#APIS_TO_ENABLE[@]} APIs..."
    if gcloud services enable "${APIS_TO_ENABLE[@]}" --project="$PROJECT_ID"; then
        echo "✓ Batch API enablement successful"
    else
        echo "Batch enable failed. Trying individual enablement..."
        for api in "${APIS_TO_ENABLE[@]}"; do
            echo "Enabling $api..."
            gcloud services enable "$api" --project="$PROJECT_ID" || {
                echo "Warning: Failed to enable $api"
            }
        done
    fi
    
    echo "Waiting for APIs to activate..."
    sleep 10
else
    echo "✓ All required APIs are already enabled"
fi

echo ""
echo "Verifying APIs..."
VERIFICATION_FAILED=false
for api in "${REQUIRED_APIS[@]}"; do
    if gcloud services list --enabled --filter="name:$api" --format="value(name)" --project="$PROJECT_ID" | grep -q "$api"; then
        echo "✓ $api verified"
    else
        echo "✗ $api failed verification"
        VERIFICATION_FAILED=true
    fi
done

if [ "$VERIFICATION_FAILED" = true ]; then
    echo ""
    echo "Error: One or more APIs failed verification."
    echo "Please check your permissions and try again."
    exit 1
fi

echo ""
echo "Setting quota project for Application Default Credentials..."
if gcloud auth application-default set-quota-project "$PROJECT_ID" 2>/dev/null; then
    echo "✓ Quota project set successfully"
else
    echo "Note: Could not set quota project (this is usually not critical)"
fi

echo ""
echo "✓ API enablement complete for project: $PROJECT_ID"

# ! --- Docker Registry --- !
REGISTRY_EXISTS=$(gcloud artifacts repositories list \
    --location="$REGION" \
    --filter="name:repositories/$DOCKER_REGISTRY_NAME" \
    --format="value(name)" \
    --quiet 2>/dev/null)

if [[ -n "$REGISTRY_EXISTS" ]]; then
    echo "Repository '$DOCKER_REGISTRY_NAME' already exists."
else
    echo "Creating Docker repository..."
    if gcloud artifacts repositories create "$DOCKER_REGISTRY_NAME" \
        --repository-format=docker \
        --location="$REGION" \
        --description="Docker repository for zetta challenge"; then
        echo "✓ Repository '$DOCKER_REGISTRY_NAME' created successfully."
    else
        echo "✗ Failed to create repository '$DOCKER_REGISTRY_NAME'"
        exit 1
    fi
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
# Proxy-Only Subnet for Internal ALB
if ! gcloud compute networks subnets describe $PROXY_ONLY_SUBNET_NAME --region=$REGION --project=$PROJECT_ID &> /dev/null; then
    echo "Proxy-only subnet '$PROXY_ONLY_SUBNET_NAME' not found in region '$REGION'. Creating it..."
    gcloud compute networks subnets create $PROXY_ONLY_SUBNET_NAME \
        --network=$VPC_NETWORK \
        --range=$PROXY_ONLY_SUBNET_CIDR \
        --region=$REGION \
        --purpose=REGIONAL_MANAGED_PROXY \
        --role=ACTIVE \
        --project=$PROJECT_ID || { echo "Failed to create proxy-only subnet."; exit 1; }
    echo "Proxy-only subnet '$PROXY_ONLY_SUBNET_NAME' created successfully with CIDR '$PROXY_ONLY_SUBNET_CIDR'."
else
    echo "Proxy-only subnet '$PROXY_ONLY_SUBNET_NAME' already exists in region '$REGION'."
fi
# ! --- VPC & Subnet --- !


# ! --- VPC Firewall --- !
echo "Creating firewall rules for internal communication..."
# Allows internal communication within VPC
# (ICMP is not required but kept for networking diagnostics)
INTERNAL_FIREWALL_RULE="allow-internal-$VPC_NETWORK"
if ! gcloud compute firewall-rules describe $INTERNAL_FIREWALL_RULE --project=$PROJECT_ID &> /dev/null; then
    echo "Creating internal firewall rule '$INTERNAL_FIREWALL_RULE'..."
    gcloud compute firewall-rules create $INTERNAL_FIREWALL_RULE \
        --network=$VPC_NETWORK \
        --allow=tcp,udp,icmp \
        --source-ranges=$SUBNET_IP_CIDR \
        --description="Allow internal communication within VPC" \
        --project=$PROJECT_ID || { echo "Failed to create internal firewall rule."; exit 1; }
else
    echo "Internal firewall rule '$INTERNAL_FIREWALL_RULE' already exists."
fi

# Allows HTTP/HTTPS traffic for load balancer health checks
# (Here HTTP should be sufficient)
LB_HEALTH_CHECK_FIREWALL_RULE="allow-lb-health-checks-$VPC_NETWORK"
if ! gcloud compute firewall-rules describe $LB_HEALTH_CHECK_FIREWALL_RULE --project=$PROJECT_ID &> /dev/null; then
    echo "Creating load balancer health check firewall rule '$LB_HEALTH_CHECK_FIREWALL_RULE'..."
    gcloud compute firewall-rules create $LB_HEALTH_CHECK_FIREWALL_RULE \
        --network=$VPC_NETWORK \
        --allow=tcp:80,tcp:443,tcp:8080 \
        --source-ranges=130.211.0.0/22,35.191.0.0/16 \
        --description="Allow Google Cloud Load Balancer health checks" \
        --project=$PROJECT_ID || { echo "Failed to create health check firewall rule."; exit 1; }
else
    echo "Load balancer health check firewall rule '$LB_HEALTH_CHECK_FIREWALL_RULE' already exists."
fi

# Allows ingress from Google's load balancer IP ranges.
#? This is in case we add more microservices on the backend.
INTERNAL_LB_FIREWALL_RULE="allow-internal-lb-$VPC_NETWORK"
if ! gcloud compute firewall-rules describe $INTERNAL_LB_FIREWALL_RULE --project=$PROJECT_ID &> /dev/null; then
    echo "Creating internal load balancer firewall rule '$INTERNAL_LB_FIREWALL_RULE'..."
    gcloud compute firewall-rules create $INTERNAL_LB_FIREWALL_RULE \
        --network=$VPC_NETWORK \
        --allow=tcp:80,tcp:443 \
        --source-ranges=10.0.0.0/8,172.16.0.0/12,192.168.0.0/16 \
        --description="Allow traffic from internal load balancer" \
        --project=$PROJECT_ID || { echo "Failed to create internal LB firewall rule."; exit 1; }
else
    echo "Internal load balancer firewall rule '$INTERNAL_LB_FIREWALL_RULE' already exists."
fi
# ! --- VPC Firewall --- !

# TODO: For 3rd Party Integrations -> Add Network Address Translation for the VPC
# e.g. In case of adding a webhook event server like a payment provider
echo "VPC networking completed."

# ! ===== To Proceed the CloudRun services need to be available ===== !
echo "Validating required Cloud Run services..."

# Check if backend API service exists
echo "Checking if Cloud Run service '$BE_API_SERVICE_NAME' exists..."
if ! gcloud run services describe $BE_API_SERVICE_NAME \
    --region=$REGION \
    --project=$PROJECT_ID \
    --format="value(metadata.name)" &> /dev/null; then
    echo "✗ Error: Cloud Run service '$BE_API_SERVICE_NAME' not found in region '$REGION'"
    echo "Please deploy the backend service before running this script."
    exit 1
else
    echo "✓ Backend service '$BE_API_SERVICE_NAME' found"
fi

# Check if frontend service exists
echo "Checking if Cloud Run service '$FE_SVELTE_SERVICE_NAME' exists..."
if ! gcloud run services describe $FE_SVELTE_SERVICE_NAME \
    --region=$REGION \
    --project=$PROJECT_ID \
    --format="value(metadata.name)" &> /dev/null; then
    echo "✗ Error: Cloud Run service '$FE_SVELTE_SERVICE_NAME' not found in region '$REGION'"
    echo "Please deploy the frontend service before running this script."
    exit 1
else
    echo "✓ Frontend service '$FE_SVELTE_SERVICE_NAME' found"
fi

echo "✓ All required Cloud Run services validated"
echo ""
# TODO: Figure out the command to map domains as this is still a preview feature by GCP


#! --- Internal Application Load Balancer ---
# Direct service to service communication patterns are preferred for low latency (K8s DNS)
# However to follow the serverless narrative regional LBs cut on cost + Cloud Armor native integration & CDN
echo "Configuring Internal Application Load Balancer..."

if ! gcloud compute network-endpoint-groups describe $BE_API_SERVICE_NEG_NAME --region=$REGION --project=$PROJECT_ID &> /dev/null; then
    echo "Creating NEG '$BE_API_SERVICE_NEG_NAME' for service '$BE_API_SERVICE_NAME'..."
    gcloud compute network-endpoint-groups create $BE_API_SERVICE_NEG_NAME \
        --region=$REGION \
        --network-endpoint-type=SERVERLESS \
        --cloud-run-service=$BE_API_SERVICE_NAME \
        --project=$PROJECT_ID || { echo "Failed to create NEG $BE_API_SERVICE_NEG_NAME."; exit 1; }
else
    echo "NEG '$BE_API_SERVICE_NEG_NAME' already exists."
fi
echo "Serverless NEGs configured."

if ! gcloud compute backend-services describe $BE_API_SERVICE_LB_LINK --region=$REGION --project=$PROJECT_ID &> /dev/null; then
    echo "Creating Backend Service '$BE_API_SERVICE_LB_LINK'..."
    gcloud compute backend-services create $BE_API_SERVICE_LB_LINK \
        --load-balancing-scheme=INTERNAL_MANAGED \
        --protocol=HTTP \
        --region=$REGION \
        --project=$PROJECT_ID || { echo "Failed to create backend service $BE_API_SERVICE_NAME."; exit 1; }
else
    echo "Backend Service '$BE_API_SERVICE_LB_LINK' already exists."
fi

if ! gcloud compute backend-services describe $BE_API_SERVICE_LB_LINK --region=$REGION --project=$PROJECT_ID --format="json" | grep -q "$BE_API_SERVICE_NEG_NAME"; then
    echo "Adding NEG '$BE_API_SERVICE_NEG_NAME' to Backend Service '$BE_API_SERVICE_LB_LINK'..."
    gcloud compute backend-services add-backend $BE_API_SERVICE_LB_LINK \
        --network-endpoint-group=$BE_API_SERVICE_NEG_NAME \
        --network-endpoint-group-region=$REGION \
        --project=$PROJECT_ID || { echo "Failed to add '$BE_API_SERVICE_LB_LINK' to NEG '$BE_API_SERVICE_NEG_NAME'."; exit 1; }
else
    echo "NEG '$BE_API_SERVICE_NEG_NAME' already associated with Backend Service '$BE_API_SERVICE_LB_LINK'."
fi
echo "LB Backend Services configured."

# TODO: IF adding multiple APIs (microservices) consider adding a validator
# TODO: It should resolve conflicting path matchers if api gateway is not used
echo "Creating LB URL Map..."
if ! gcloud compute url-maps describe $URL_MAP_NAME --region=$REGION --project=$PROJECT_ID &> /dev/null; then
    echo "URL Map '$URL_MAP_NAME' not found. Creating..."
    gcloud compute url-maps create $URL_MAP_NAME \
        --default-service $BE_API_SERVICE_LB_LINK \
        --region=$REGION \
        --project=$PROJECT_ID || { echo "Failed to create URL Map."; exit 1; }
else
    echo "URL Map '$URL_MAP_NAME' already exists. Checking for updates..."
    CURRENT_DEFAULT_SERVICE=$(gcloud compute url-maps describe $URL_MAP_NAME --region=$REGION --project=$PROJECT_ID --format="value(defaultService)" | awk -F'/' '{print $NF}')
    if [ "$CURRENT_DEFAULT_SERVICE" != "$BE_API_SERVICE_LB_LINK" ]; then
        echo "Updating default service for URL Map '$URL_MAP_NAME' to '$BE_API_SERVICE_LB_LINK'."
        gcloud compute url-maps update $URL_MAP_NAME \
            --default-service $BE_API_SERVICE_LB_LINK \
            --region=$REGION \
            --project=$PROJECT_ID || { echo "Failed to update default service for URL Map."; exit 1; }
    fi
fi
echo "Load Balancer path matcher setup..."
        
if ! gcloud compute url-maps describe $URL_MAP_NAME --region=$REGION --project=$PROJECT_ID --format="json" | jq '.pathMatchers[]? | select(.name == "api-path-matcher")' | grep -q "api-path-matcher"; then
    echo "Adding comprehensive path matcher..."
    gcloud compute url-maps add-path-matcher $URL_MAP_NAME \
        --path-matcher-name="api-path-matcher" \
        --default-service $BE_API_SERVICE_LB_LINK \
        --region=$REGION \
        --project=$PROJECT_ID || { echo "Failed to add path matcher to URL Map."; exit 1; }
    # To add another service you can do so via path rule
    # --path-rules="/payment-api/*=$PAYMENT_API_SERVICE_NAME"
else
    echo "Comprehensive path matcher already exists."
fi
echo "LB URL Map configured."

echo "Creating SSL Certificate for internal HTTPS..."
if ! gcloud compute ssl-certificates describe $SSL_CERT_NAME --region=$REGION --project=$PROJECT_ID &> /dev/null; then
    
    # echo "Creating self-signed SSL certificate '$SSL_CERT_NAME'..."
    # openssl req -x509 -newkey rsa:2048 -keyout temp-key.pem -out temp-cert.pem -days 365 -nodes \
    #     -subj "/CN=$INTERNAL_HOSTNAME" || { echo "Failed to generate certificate"; exit 1; }
    
    gcloud compute ssl-certificates create $SSL_CERT_NAME \
        --certificate=temp-cert.pem \
        --private-key=temp-key.pem \
        --region=$REGION \
        --project=$PROJECT_ID || { echo "Failed to create SSL certificate."; exit 1; }
    
    # rm -f temp-cert.pem temp-key.pem
    
    echo "SSL certificate '$SSL_CERT_NAME' created successfully."
else
    echo "SSL certificate '$SSL_CERT_NAME' already exists."
fi

if ! gcloud compute target-https-proxies describe $PROXY_NAME --region=$REGION --project=$PROJECT_ID &> /dev/null; then
    echo "Creating HTTPS Proxy '$PROXY_NAME'..."
    gcloud compute target-https-proxies create $PROXY_NAME \
        --url-map $URL_MAP_NAME \
        --ssl-certificates $SSL_CERT_NAME \
        --region=$REGION \
        --project=$PROJECT_ID || { echo "Failed to create HTTPS Proxy."; exit 1; }
else
    echo "HTTPS Proxy '$PROXY_NAME' already exists."
    CURRENT_URL_MAP=$(gcloud compute target-https-proxies describe $PROXY_NAME --region=$REGION --project=$PROJECT_ID --format="value(urlMap)" | awk -F'/' '{print $NF}')
    if [ "$CURRENT_URL_MAP" != "$URL_MAP_NAME" ]; then
        echo "Warning: Proxy '$PROXY_NAME' linked to different URL map. Manual intervention might be needed as direct update is not straightforward."
    fi
fi
echo "Internal HTTPS Proxy configured."

echo "Creating Internal Forwarding Rule..."
#? Reserve a static internal IP address if none use the same name
if ! gcloud compute addresses describe $INTERNAL_ALB_IP_ADDRESS_NAME --region=$REGION --project=$PROJECT_ID &> /dev/null; then
    echo "Reserving static internal IP address '$INTERNAL_ALB_IP_ADDRESS_NAME'..."
    gcloud compute addresses create $INTERNAL_ALB_IP_ADDRESS_NAME \
        --region=$REGION \
        --subnet=$SUBNET_NAME \
        --addresses=$IP_TO_ASSIGN \
        --purpose=SHARED_LOADBALANCER_VIP \
        --project=$PROJECT_ID || { echo "Failed to reserve internal IP."; exit 1; }
else
    echo "Static internal IP address '$INTERNAL_ALB_IP_ADDRESS_NAME' already exists."
fi

#TODO: Wait for the IP address to be reserved properly
sleep 10
export INTERNAL_IP=$(gcloud compute addresses describe $INTERNAL_ALB_IP_ADDRESS_NAME \
    --region=$REGION \
    --format='value(address)' \
    --project=$PROJECT_ID)

if ! gcloud compute forwarding-rules describe $FORWARDING_RULE_NAME --region=$REGION --project=$PROJECT_ID &> /dev/null; then
    echo "Creating Forwarding Rule '$FORWARDING_RULE_NAME'..."
    gcloud compute forwarding-rules create $FORWARDING_RULE_NAME \
        --load-balancing-scheme=INTERNAL_MANAGED \
        --network=$VPC_NETWORK \
        --subnet=$SUBNET_NAME \
        --address=$INTERNAL_IP \
        --ports=443 \
        --region=$REGION \
        --target-https-proxy=$PROXY_NAME \
        --target-https-proxy-region=$REGION \
        --project=$PROJECT_ID || { echo "Failed to create Forwarding Rule."; exit 1; }
else
    echo "Forwarding Rule '$FORWARDING_RULE_NAME' already exists."
fi
echo "Internal Forwarding Rule configured."
echo "Internal Load Balancer IP Address: $INTERNAL_IP"
#! --- Internal Application Load Balancer ---


#! --- Internal DNS ---
echo "Configuring Internal Cloud DNS Records..."

if ! gcloud dns managed-zones describe $MANAGED_ZONE_NAME --project=$PROJECT_ID &> /dev/null; then
    echo "Creating private DNS managed zone '$MANAGED_ZONE_NAME'..."
    gcloud dns managed-zones create $MANAGED_ZONE_NAME \
        --dns-name=$DNS_SUFFIX \
        --description="Private DNS for internal APIs" \
        --visibility="private" \
        --networks=$VPC_NETWORK \
        --project=$PROJECT_ID || { echo "Failed to create DNS managed zone."; exit 1; }
else
    echo "Private DNS managed zone '$MANAGED_ZONE_NAME' already exists."
fi

if ! gcloud dns record-sets describe "$INTERNAL_HOSTNAME." --type="A" --zone=$MANAGED_ZONE_NAME --project=$PROJECT_ID &> /dev/null; then
    echo "A record for '$INTERNAL_HOSTNAME' not found. Creating..."
    gcloud dns record-sets create "$INTERNAL_HOSTNAME." \
        --rrdatas=$INTERNAL_IP \
        --type="A" \
        --ttl="300" \
        --zone=$MANAGED_ZONE_NAME \
        --project=$PROJECT_ID || { echo "Failed to create A record."; exit 1; }
else
    CURRENT_IP=$(gcloud dns record-sets describe "$INTERNAL_HOSTNAME." --type="A" --zone=$MANAGED_ZONE_NAME --project=$PROJECT_ID --format="value(rrdatas[0])")
    if [ "$CURRENT_IP" != "$INTERNAL_IP" ]; then
        echo "A record for '$INTERNAL_HOSTNAME' exists but points to a different IP. Updating..."
        gcloud dns record-sets delete "$INTERNAL_HOSTNAME." \
            --type="A" \
            --zone=$MANAGED_ZONE_NAME \
            --project=$PROJECT_ID -q || { echo "Failed to delete old A record for update."; exit 1; }
        gcloud dns record-sets create "$INTERNAL_HOSTNAME." \
            --rrdatas=$INTERNAL_IP \
            --type="A" \
            --ttl="300" \
            --zone=$MANAGED_ZONE_NAME \
            --project=$PROJECT_ID || { echo "Failed to create updated A record."; exit 1; }
    else
        echo "A record for '$INTERNAL_HOSTNAME' already exists and points to '$INTERNAL_IP'."
    fi
fi
echo "Internal DNS configured."
echo "Internal API Hostname: $INTERNAL_HOSTNAME"
#! --- Internal DNS ---

echo "Updating Cloud Run services networking & variables..."
#TODO: Loose end - hardcoded Env var for BE endpoint in FE configs
#TODO: Overriding ingress/egress settings to fit LB setup
#TODO: Update log after proper interpolation of vars
echo "Updating $FE_SVELTE_SERVICE_NAME..."
gcloud run services update $FE_SVELTE_SERVICE_NAME \
    --update-env-vars PUBLIC_API_URL="https://$INTERNAL_HOSTNAME" \
    --network=$VPC_NETWORK \
    --subnet=$SUBNET_NAME \
    --platform managed \
    --region $REGION \
    --ingress "all" \
    --vpc-egress "all-traffic" \
    --project $PROJECT_ID || { echo "Failed to update env vars for $FE_SVELTE_SERVICE_NAME."; exit 1; }
echo "Environment variables updated."

echo "Updating $BE_API_SERVICE_NAME..."
gcloud run services update $BE_API_SERVICE_NAME \
    --network=$VPC_NETWORK \
    --subnet=$SUBNET_NAME \
    --platform managed \
    --region $REGION \
    --ingress "internal" \
    --vpc-egress "all-traffic" \
    --project $PROJECT_ID || { echo "Failed to update env vars for $BE_API_SERVICE_NAME."; exit 1; }
echo "Environment variables updated."

echo "--- Deployment Script Finished ---"
echo "Your internal API endpoint is: https://$INTERNAL_HOSTNAME"
echo "Cloud Run URLs:"
gcloud run services describe $FE_SVELTE_SERVICE_NAME --platform managed --region $REGION --format 'value(status.url)' --project $PROJECT_ID
gcloud run services describe $BE_API_SERVICE_NAME --platform managed --region $REGION --format 'value(status.url)' --project $PROJECT_ID
# TODO: Add aditional configuration info
# TODO: Add monitoring logs URLS and docs