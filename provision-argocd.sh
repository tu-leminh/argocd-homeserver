#!/bin/bash
#
# This script bootstraps a GitOps-managed homelab server using MicroK8s.
# It prepares the server and deploys the root ArgoCD application, which then
# manages the rest of the cluster setup via GitOps.
#

set -euo pipefail

# --- Configuration ---
# The namespace where ArgoCD will be installed by the GitOps process.
readonly ARGOCD_NAMESPACE="argocd"

# --- Helper Functions ---
info() {
    echo "[INFO] $1"
}

error() {
    echo "[ERROR] $1" >&2
    exit 1
}

# --- Pre-flight Checks ---
info "Updating package list and installing dependencies..."
sudo apt-get update
sudo apt-get install -y ranger htop neovim

info "Installing k9s..."
if ! command -v k9s &> /dev/null; then
    sudo snap install k9s
else
    info "k9s is already installed."
fi

info "Starting pre-flight checks..."
if ! command -v microk8s &> /dev/null; then
    info "MicroK8s not found. Installing..."
    sudo snap install microk8s --classic
    sudo usermod -a -G microk8s $USER
    info "MicroK8s installed. Please log out and log back in, then re-run this script."
    exit 0
else
    info "MicroK8s is already installed."
fi

# --- MicroK8s Setup ---
info "Configuring MicroK8s..."
microk8s status --wait-ready
info "Enabling essential MicroK8s add-ons (dns, storage)..."
microk8s enable dns storage
microk8s status --wait-ready

# --- ArgoCD Namespace and Root App ---
info "Creating ArgoCD namespace: ${ARGOCD_NAMESPACE}"
if ! microk8s kubectl get namespace "${ARGOCD_NAMESPACE}" &> /dev/null; then
    microk8s kubectl create namespace "${ARGOCD_NAMESPACE}"
else
    info "Namespace '${ARGOCD_NAMESPACE}' already exists."
fi

info "Applying the root 'App of Apps' manifest..."
if [ ! -f "argo-cd/bootstrap/root-application.yaml" ]; then
    error "Root application manifest not found at 'argo-cd/bootstrap/root-application.yaml'. Make sure you are running this script from the repository root."
fi
microk8s kubectl apply -f argo-cd/bootstrap/root-application.yaml

# --- Post-Installation Instructions ---
info "Server bootstrapping is complete!"
info "--------------------------------------------------"
info "The root ArgoCD application has been deployed."
info "ArgoCD will now self-install and deploy the other applications from your Git repository."
info "Monitor the progress with: microk8s kubectl get pods -n ${ARGOCD_NAMESPACE} -w"
info ""
info "Once the 'argocd-server' pod is running, you can access the UI:"
info "1. Port-forward the ArgoCD server:"
echo "   microk8s kubectl port-forward svc/argocd-server -n ${ARGOCD_NAMESPACE} 8080:443"
info "2. Access the UI at: https://localhost:8080"
info "3. Log in with the username 'admin' and the initial password:"
echo "   microk8s kubectl -n ${ARGOCD_NAMESPACE} get secret argocd-initial-admin-secret -o jsonpath=\"{.data.password}\" | base64 -d"
info "--------------------------------------------------"
