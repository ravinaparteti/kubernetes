#!/bin/bash

# Function to retrieve secrets from Secret Manager
retrieve_secret() {
    : """
    Retrieve the latest version of a secret from Google Cloud Secret Manager.
    
    This function securely fetches the latest version of a specified secret from 
    Google Cloud Secret Manager, ensuring sensitive credentials are not hardcoded.
    
    Args:
        $1 (string): The name of the secret to retrieve.
    
    Returns:
        string: The secret value retrieved from Secret Manager.
    """

    gcloud secrets versions access latest --secret="$1"
}

GCP_PROJECT=$(retrieve_secret "k8s-gcp-project-dev")
REGION=$(retrieve_secret "k8s-region-dev")
REPO_NAME=$(retrieve_secret "k8s-repo-name-dev")
TAG=$(retrieve_secret "k8s-tag-dev")
_ACCESS_TOKEN=$(retrieve_secret "github-secret")
NAMESPACE=$(retrieve_secret "k8s-namespace")

# Function to authenticate with GKE if needed
authenticate_gke() {
    if ! kubectl get nodes > /dev/null 2>&1; then
        echo "Authenticating to GKE cluster..."
        gcloud container clusters get-credentials cluster --region $REGION --project $GCP_PROJECT
    else
        echo "Already authenticated to GKE cluster."
    fi
}



git config --global url."https://$_ACCESS_TOKEN@github.com/".insteadOf "https://github.com/"
git clone https://github.com/ravinaparteti/kubernetes.git
git fetch --unshallow

# Define function folders for Kubernetes deployment
declare -A folders=(
    ["categorization"]="categorization_tool"
    ["summarization"]="summarization_vm"
    ["similarity"]="similarity_vm"
    ["discover"]="discover"
)

# Retrieve and store environment variables in Secret Manager and ConfigMaps
retrieve_and_store_env() {
    local name=$1
    local secret_name="${name}-k8s-env"
    local env_file="/tmp/${name}-k8s.env"

    # retrieve_secret "$secret_name" "$env_file"
    gcloud secrets versions access latest --secret="$secret_name" > "$env_file"
    
    echo "Updating ConfigMap for $name..."
    kubectl delete configmap "${name}-env-config" -n "$NAMESPACE" --ignore-not-found
    kubectl create configmap "${name}-env-config" --from-env-file="$env_file" -n "$NAMESPACE"
}

# Build and push Docker image to Artifact Registry
build_and_push_image() {
    local name=$1
    local path="${folders[$name]}"
    local image_name="$REGION-docker.pkg.dev/$GCP_PROJECT/$REPO_NAME/${name}:$TAG"
    
    gcloud secrets versions access latest --secret="${name}-k8s-env" > "$path/${name}.env"
    
    echo "Building and pushing Docker image for $name..."
    docker build -t "$image_name" "$path"
    docker push "$image_name"
}

# Deploy function on Kubernetes with updated deployment.yaml
deploy_k8s_pod() {
    local name=$1
    local path=$2
    
    retrieve_and_store_env "$name"

    # Navigate to the function directory safely
    if [ -d "$path" ]; then 
        cd "$path" || exit 1
        pwd
    else 
        echo "Error: Directory $path not found" 
        exit 1
    fi

    echo "Copying 'utils' folder for $name deployment"
    cp -r "$(git rev-parse --show-toplevel)/utils" .
    echo "Retrieving 'service-account.json' from Secret Manager..."
    gcloud secrets versions access latest --secret="service-account" > key.json

    cd - || exit 1
    
    build_and_push_image "$name"

    # Fetch deployment.yaml from Secret Manager
    local yaml_file="/tmp/${name}-deployment.yaml"
    echo "Retrieving '${name}-deployment.yaml' from Secret Manager..."
    gcloud secrets versions access latest --secret="${name}-deployment-yaml" > ${name}-deployment.yaml


    # echo "Deploying '$name' on Kubernetes..."
    kubectl apply -f "$yaml_file"

    # Force pod restart to ensure new image is used
    echo "Restarting pods for $name..."
    kubectl rollout restart deployment "$name" -n $NAMESPACE

    echo "Waiting for 30 seconds to allow the pod to start..."
    sleep 30
}

utils_changed=false
if ! git diff --quiet HEAD~1 HEAD -- "utils"; then
    utils_changed=true
fi

# Authenticate to GKE before deployment
authenticate_gke

# Deploy functions only if changes are detected
for name in "${!folders[@]}"; do
    folder_changed=false
    if ! git diff --quiet HEAD~1 HEAD -- "${folders[$name]}" || [ "$utils_changed" = true ]; then
        folder_changed=true
    fi
    
    if [ "$folder_changed" = true ]; then
        deploy_k8s_pod "$name" "${folders[$name]}"
    else
        echo "Skipping deployment for $name, no changes detected."
    fi
done
