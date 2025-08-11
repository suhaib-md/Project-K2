.PHONY: help setup deploy destroy clean status test ssh-controller ssh-worker logs

# Default target
help:
	@echo "Kubernetes The Hard Way - Terraform Automation"
	@echo ""
	@echo "Available targets:"
	@echo "  setup           - Set up WSL environment and tools"
	@echo "  init            - Initialize Terraform"
	@echo "  plan            - Plan Terraform deployment"
	@echo "  deploy          - Deploy complete infrastructure and K8s"
	@echo "  destroy         - Destroy all resources"
	@echo "  clean           - Clean local files and state"
	@echo "  status          - Check cluster status"
	@echo "  test            - Run cluster tests"
	@echo "  logs            - Show recent logs from all nodes"
	@echo "  ssh-controller  - SSH to controller-0"
	@echo "  ssh-worker      - SSH to worker-0"
	@echo "  restart         - Restart all services"
	@echo ""
	@echo "Quick start: make setup && make deploy"

setup:
	@echo "Setting up WSL environment..."
	./setup-wsl-jumpbox.sh

init:
	@echo "Initializing Terraform..."
	terraform init

plan:
	@echo "Planning Terraform deployment..."
	terraform plan -out=tfplan

deploy:
	@echo "Deploying infrastructure and Kubernetes..."
	./deploy-all.sh

destroy:
	@echo "Destroying all resources..."
	@read -p "Are you sure you want to destroy all resources? (yes/no): " confirm; \
	if [ "$$confirm" = "yes" ]; then \
		terraform destroy -auto-approve; \
	else \
		echo "Destroy cancelled."; \
	fi

clean:
	@echo "Cleaning local files..."
	rm -rf .terraform/ *.tfstate* *.tfplan
	rm -rf certs/ kubeconfigs/
	rm -f *.pem *.kubeconfig ssh_config inventory.ini encryption-config.yaml

status:
	@echo "Checking cluster status..."
	@if [ -f admin.kubeconfig ]; then \
		export KUBECONFIG=$$PWD/admin.kubeconfig; \
		kubectl get nodes -o wide; \
		echo ""; \
		kubectl get pods --all-namespaces; \
	else \
		echo "admin.kubeconfig not found. Run 'make deploy' first."; \
	fi

test:
	@echo "Running cluster tests..."
	@export KUBECONFIG=$$PWD/admin.kubeconfig; \
	echo "=== Testing cluster connectivity ==="; \
	kubectl cluster-info; \
	echo ""; \
	echo "=== Testing pod deployment ==="; \
	kubectl run test-pod --image=nginx --restart=Never --rm -it -- curl -I localhost; \
	echo ""; \
	echo "=== Testing service creation ==="; \
	kubectl create deployment test-nginx --image=nginx; \
	kubectl expose deployment test-nginx --port=80 --type=NodePort; \
	kubectl get svc test-nginx; \
	kubectl delete deployment test-nginx; \
	kubectl delete service test-nginx

ssh-controller:
	@if [ -f ssh_config ]; then \
		ssh -F ssh_config controller-0; \
	else \
		echo "ssh_config not found. Run 'make deploy' first."; \
	fi

ssh-worker:
	@if [ -f ssh_config ]; then \
		ssh -F ssh_config worker-0; \
	else \
		echo "ssh_config not found. Run 'make deploy' first."; \
	fi

logs:
	@echo "Fetching recent logs from all nodes..."
	@if [ -f ssh_config ]; then \
		echo "=== Controller-0 API Server Logs ==="; \
		ssh -F ssh_config controller-0 'sudo journalctl -u kube-apiserver --lines=10 --no-pager'; \
		echo ""; \
		echo "=== Controller-0 etcd Logs ==="; \
		ssh -F ssh_config controller-0 'sudo journalctl -u etcd --lines=10 --no-pager'; \
		echo ""; \
		echo "=== Worker-0 kubelet Logs ==="; \
		ssh -F ssh_config worker-0 'sudo journalctl -u kubelet --lines=10 --no-pager'; \
	else \
		echo "ssh_config not found. Run 'make deploy' first."; \
	fi

restart:
	@echo "Restarting all services..."
	@if [ -f helper-scripts/restart-services.sh ]; then \
		./helper-scripts/restart-services.sh; \
	else \
		echo "restart-services.sh not found. Run 'make deploy' first."; \
	fi

# Development targets
dev-setup:
	@echo "Setting up development environment..."
	./create-project-structure.sh

validate:
	@echo "Validating Terraform configuration..."
	terraform validate
	terraform fmt -check

format:
	@echo "Formatting Terraform files..."
	terraform fmt -recursive