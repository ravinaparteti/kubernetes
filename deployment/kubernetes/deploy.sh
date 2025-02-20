#!/bin/bash

# Function to authenticate with GKE if needed
authenticate_gke() {
    if ! kubectl get nodes > /dev/null 2>&1; then
        echo "Authenticating to GKE cluster..."
        gcloud container clusters get-credentials cluster --region us-central1 --project prince-project-446008
    else
        echo "Already authenticated to GKE cluster."
    fi
}


# Function to retrieve secrets from Secret Manager and store in a file
retrieve_secret() {
    local secret_name=$1
    local output_file=$2
    echo "Retrieving secret: $secret_name"
    gcloud secrets versions access latest --secret="$secret_name" > "$output_file"
}

_ACCESS_TOKEN=$(gcloud secrets versions access latest --secret="github-secret")

git config --global url."https://$_ACCESS_TOKEN@github.com/".insteadOf "https://github.com/"
git clone https://github.com/ravinaparteti/kubernetes.git
git fetch --unshallow

# Define function folders for Kubernetes deployment
declare -A function_folders=(
    ["categorization"]="categorization_tool"
    ["summarization"]="summarization_vm"
    ["similarity"]="similarity_vm"
    ["discover"]="discover"
)

# Retrieve and store environment variables in Secret Manager and ConfigMaps
retrieve_and_store_env() {
    local function_name=$1
    local secret_name="${function_name}-k8s-env"
    local env_file="/tmp/${function_name}-k8s.env"
    local namespace="test"  # Set your namespace here
    
    retrieve_secret "$secret_name" "$env_file"
    
    echo "Updating ConfigMap for $function_name..."
    kubectl delete configmap "${function_name}-env-config" -n "$namespace" --ignore-not-found
    kubectl create configmap "${function_name}-env-config" --from-env-file="$env_file" -n "$namespace"
}

# Build and push Docker image to Artifact Registry
build_and_push_image() {
    local function_name=$1
    local path="${function_folders[$function_name]}"
    local image_name="us-central1-docker.pkg.dev/prince-project-446008/test/${function_name}:latest"

    echo "Building and pushing Docker image for $function_name..."
    docker build -t "$image_name" "$path"
    docker push "$image_name"
}

# Deploy function on Kubernetes with updated deployment.yaml
deploy_k8s_pod() {
    local name=$1
    local path=$2
    
    retrieve_and_store_env "$name"

    pwd    
    # Navigate to the function directory safely
    if [ -d "$path" ]; then 
        cd "$path" || exit 1
        pwd
    else 
        echo "Error: Directory $path not found" 
        exit 1
    fi
    
    pwd
    echo "Copying 'utils' folder for $name deployment"
    cp -r "$(git rev-parse --show-toplevel)/utils" .

    cd - || exit 1
    
    build_and_push_image "$name"

    # Fetch deployment.yaml from Secret Manager
    local yaml_file="/tmp/${name}-deployment.yaml"
    retrieve_secret "${name}-deployment-yaml" "$yaml_file"

    echo "Deploying '$name' on Kubernetes..."
    kubectl apply -f "$yaml_file"
}

utils_changed=false
if ! git diff --quiet HEAD~1 HEAD -- "utils"; then
    utils_changed=true
fi

# Authenticate to GKE before deployment
authenticate_gke

# Deploy functions only if changes are detected
for function_name in "${!function_folders[@]}"; do
    folder_changed=false
    if ! git diff --quiet HEAD~1 HEAD -- "${function_folders[$function_name]}" || [ "$utils_changed" = true ]; then
        folder_changed=true
    fi
    
    if [ "$folder_changed" = true ]; then
        deploy_k8s_pod "$function_name" "${function_folders[$function_name]}"
    else
        echo "Skipping deployment for $function_name, no changes detected."
    fi
done
