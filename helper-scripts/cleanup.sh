#!/bin/bash
echo "This will destroy all AWS resources created by Terraform."
read -p "Are you sure? (yes/no): " confirm
if [ "$confirm" = "yes" ]; then
    terraform destroy -auto-approve
    echo "Cleanup completed!"
else
    echo "Cleanup cancelled."
fi
