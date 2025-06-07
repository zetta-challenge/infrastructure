#!/bin/bash
set -e
cd ..

#TODO: Add a root project path to the other configs
###########################################
# CONFIGURATION VARIABLES
###########################################
# Project settings
export PROJECT_ID=${PROJECT_ID:-"devops-realm"}

# Deployment service account settings
export DEPLOY_SA_NAME=${DEPLOY_SA_NAME:-"deployment-sa"}
export DEPLOY_SA_EMAIL="${DEPLOY_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
export DEPLOY_SA_KEY_FILE=${DEPLOY_SA_KEY_FILE:-"${DEPLOY_SA_NAME}-key.json"}

# Your user email (for granting permissions)
export USER_EMAIL=${USER_EMAIL:-"decyferops@gmail.com"}

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Print section header
section() {
  echo -e "\n${YELLOW}==== $1 ====${NC}"
}

check_prerequisites() {
  section "Checking Prerequisites"
  
  if ! command -v gcloud &> /dev/null; then
    echo -e "${RED}gcloud CLI is not installed. Please install it first.${NC}"
    echo "https://cloud.google.com/sdk/docs/install"
    exit 1
  fi
  
  if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "@"; then
    echo "Not logged in to gcloud. Running login..."
    gcloud auth login
  fi
  
  if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
    echo -e "${RED}Project $PROJECT_ID does not exist. Please create it first.${NC}"
    exit 1
  fi
  
  gcloud config set project "$PROJECT_ID"
  echo -e "${GREEN}All prerequisites satisfied.${NC}"
}

# Create deployment service account
create_deploy_sa() {
  section "Creating deployment service account"
  
  # Check if deployment service account exists
  if ! gcloud iam service-accounts describe "$DEPLOY_SA_EMAIL" &> /dev/null; then
    echo "Creating deployment service account..."
    gcloud iam service-accounts create "$DEPLOY_SA_NAME" \
      --description="Service account for infrastructure deployments" \
      --display-name="Infrastructure Deployment"
    echo -e "${GREEN}Deployment service account created successfully.${NC}"
  else
    echo "Deployment service account '$DEPLOY_SA_EMAIL' already exists."
  fi
}

grant_permissions() {
  section "Granting permissions to deployment service account"
  
  echo "Granting IAM roles to $DEPLOY_SA_EMAIL..."
  
  # Manage service accounts
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:$DEPLOY_SA_EMAIL" \
    --role="roles/iam.serviceAccountAdmin" \
    --quiet
  
  # Act as other service accounts
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:$DEPLOY_SA_EMAIL" \
    --role="roles/iam.serviceAccountUser" \
    --quiet
  
  # Deploy to Cloud Run
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:$DEPLOY_SA_EMAIL" \
    --role="roles/run.admin" \
    --quiet
  
  # Role to use VPC connectors
  # gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  #   --member="serviceAccount:$DEPLOY_SA_EMAIL" \
  #   --role="roles/vpcaccess.user" \
  #   --quiet
  
  # Artifact Registry
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:$DEPLOY_SA_EMAIL" \
    --role="roles/artifactregistry.admin" \
    --quiet
  
  # VPC networks
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:$DEPLOY_SA_EMAIL" \
    --role="roles/compute.networkAdmin" \
    --quiet
    
  # Firewall Rules
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:$DEPLOY_SA_EMAIL" \
    --role="roles/compute.securityAdmin" \
    --quiet
  
  # Impersonate the deployment service account
  echo "Granting impersonation permission to $USER_EMAIL..."
  gcloud iam service-accounts add-iam-policy-binding "$DEPLOY_SA_EMAIL" \
    --member="user:$USER_EMAIL" \
    --role="roles/iam.serviceAccountTokenCreator" \
    --quiet
  
  echo -e "${GREEN}Permissions granted successfully.${NC}"
}

create_sa_key() {
  section "Creating service account key"
  
  read -p "Do you want to create a key file for this service account? (y/N): " create_key
  if [[ "$create_key" == "y" || "$create_key" == "Y" ]]; then
    if [[ -f "$DEPLOY_SA_KEY_FILE" ]]; then
      read -p "Key file $DEPLOY_SA_KEY_FILE already exists. Overwrite? (y/N): " overwrite
      if [[ "$overwrite" != "y" && "$overwrite" != "Y" ]]; then
        echo "Skipping key creation."
        return
      fi
    fi
    
    echo "Creating service account key..."
    gcloud iam service-accounts keys create "$DEPLOY_SA_KEY_FILE" \
      --iam-account="$DEPLOY_SA_EMAIL"
    
    echo -e "${GREEN}Key created: $DEPLOY_SA_KEY_FILE${NC}"
    echo "IMPORTANT: Store this key securely and do not commit it to version control."
  else
    echo "Skipping key creation. You can use service account impersonation instead."
  fi
}

# ! --- INSTRUCTIONS --- !
show_instructions() {
  section "Usage Instructions"
  
  echo -e "${GREEN}Deployment service account setup complete!${NC}"
  echo -e "Service Account: ${YELLOW}$DEPLOY_SA_EMAIL${NC}"
  
  echo -e "\n${YELLOW}To use this service account via impersonation (recommended):${NC}"
  echo "gcloud --impersonate-service-account=\"$DEPLOY_SA_EMAIL\" [commands]"
  
  echo -e "\n${YELLOW}Example to run your infrastructure script:${NC}"
  echo "gcloud --impersonate-service-account=\"$DEPLOY_SA_EMAIL\" compute networks vpc-access connectors create [...]"
  echo "gcloud --impersonate-service-account=\"$DEPLOY_SA_EMAIL\" run deploy [...]"
  
  echo -e "\n${YELLOW}Or run the entire infrastructure script with impersonation:${NC}"
  echo "GOOGLE_CLOUD_AUTH_IMPERSONATE_SERVICE_ACCOUNT=\"$DEPLOY_SA_EMAIL\" ./infrastructure-setup.sh"
  
  if [[ -f "$DEPLOY_SA_KEY_FILE" ]]; then
    echo -e "\n${YELLOW}To use this service account via key file:${NC}"
    echo "gcloud auth activate-service-account --key-file=\"$DEPLOY_SA_KEY_FILE\""
    echo "./infrastructure-setup.sh"
    echo "gcloud config set account \"$USER_EMAIL\"  # Switch back when done"
  fi
}

main() {
  section "Deployment Service Account Setup"
  echo "Project: $PROJECT_ID"
  echo "Deployment SA: $DEPLOY_SA_NAME"
  echo "User Email: $USER_EMAIL"
  
  check_prerequisites
  create_deploy_sa
  grant_permissions
  create_sa_key
  show_instructions
}

main