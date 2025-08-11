#!/bin/bash
echo "=== Kubernetes Cluster Status ==="
if [ -f admin.kubeconfig ]; then
    export KUBECONFIG=$PWD/admin.kubeconfig
    echo "Nodes:"
    kubectl get nodes -o wide
    echo ""
    echo "Pods:"
    kubectl get pods --all-namespaces
    echo ""
    echo "Services:"
    kubectl get svc --all-namespaces
else
    echo "admin.kubeconfig not found. Deploy first with 'make deploy'"
fi
