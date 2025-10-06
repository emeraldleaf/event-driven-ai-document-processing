#!/bin/bash

set -e

echo "=== Azure Infrastructure Validation Script ==="
echo "This script validates the Terraform configuration without deploying resources"
echo

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Check if required tools are installed
check_tools() {
    print_status $YELLOW "Checking required tools..."

    if ! command -v terraform &> /dev/null; then
        print_status $RED "ERROR: Terraform is not installed"
        exit 1
    fi

    if ! command -v az &> /dev/null; then
        print_status $RED "ERROR: Azure CLI is not installed"
        exit 1
    fi

    print_status $GREEN "✓ Required tools are installed"
}

# Check Azure CLI login status
check_azure_login() {
    print_status $YELLOW "Checking Azure CLI authentication..."

    if ! az account show &> /dev/null; then
        print_status $RED "ERROR: Not logged in to Azure CLI"
        print_status $YELLOW "Please run: az login"
        exit 1
    fi

    local subscription=$(az account show --query name -o tsv)
    print_status $GREEN "✓ Authenticated to Azure subscription: $subscription"
}

# Validate Terraform configuration
validate_terraform() {
    print_status $YELLOW "Validating Terraform configuration..."

    if [ ! -f "terraform.tfvars" ]; then
        print_status $RED "ERROR: terraform.tfvars file not found"
        print_status $YELLOW "Please copy terraform.tfvars.example to terraform.tfvars and update the values"
        exit 1
    fi

    # Run comprehensive syntax check
    print_status $YELLOW "Running comprehensive Terraform syntax validation..."
    if [ -f "./terraform-syntax-check.sh" ]; then
        if ./terraform-syntax-check.sh; then
            print_status $GREEN "✓ Comprehensive syntax validation passed"
        else
            print_status $RED "ERROR: Syntax validation failed"
            exit 1
        fi
    else
        # Fallback to basic validation if syntax check script not found
        print_status $YELLOW "terraform-syntax-check.sh not found, running basic validation..."

        # Initialize Terraform
        print_status $YELLOW "Initializing Terraform..."
        terraform init -backend=false

        # Format check
        print_status $YELLOW "Checking Terraform formatting..."
        if ! terraform fmt -check=true -diff=true; then
            print_status $YELLOW "WARNING: Terraform files are not properly formatted"
            print_status $YELLOW "Run 'terraform fmt' to fix formatting"
        else
            print_status $GREEN "✓ Terraform files are properly formatted"
        fi

        # Validate configuration
        print_status $YELLOW "Validating Terraform configuration..."
        terraform validate
        print_status $GREEN "✓ Terraform configuration is valid"
    fi
}

# Plan the deployment (dry run)
plan_deployment() {
    print_status $YELLOW "Creating Terraform execution plan (dry run)..."

    # Create plan file
    terraform plan -out=tfplan -detailed-exitcode
    local plan_exit_code=$?

    case $plan_exit_code in
        0)
            print_status $GREEN "✓ No changes needed - infrastructure matches configuration"
            ;;
        1)
            print_status $RED "ERROR: Terraform plan failed"
            exit 1
            ;;
        2)
            print_status $GREEN "✓ Plan created successfully - changes would be applied"

            # Show resource count
            local resource_count=$(terraform show -json tfplan | jq '.resource_changes | length')
            print_status $YELLOW "Resources to be created/modified: $resource_count"
            ;;
    esac
}

# Validate Azure resources and configurations
validate_azure_resources() {
    print_status $YELLOW "Validating Azure-specific configurations..."

    # Check if the specified Azure Front Door exists
    local front_door_id=$(terraform output -raw existing_front_door_id 2>/dev/null || echo "")
    if [ -n "$front_door_id" ]; then
        # Extract resource group and name from resource ID
        local rg_name=$(echo $front_door_id | cut -d'/' -f5)
        local fd_name=$(echo $front_door_id | cut -d'/' -f9)

        if az cdn profile show --name "$fd_name" --resource-group "$rg_name" &> /dev/null; then
            print_status $GREEN "✓ Azure Front Door exists and is accessible"
        else
            print_status $RED "ERROR: Cannot access specified Azure Front Door"
            print_status $YELLOW "Please verify the Front Door resource ID in terraform.tfvars"
        fi
    fi

    # Check resource name availability
    print_status $YELLOW "Checking resource name availability..."

    # Generate resource names based on variables
    local app_name=$(grep 'app_name' terraform.tfvars | cut -d'=' -f2 | tr -d ' "')
    local environment=$(grep 'environment' terraform.tfvars | cut -d'=' -f2 | tr -d ' "')
    local location=$(grep 'location' terraform.tfvars | cut -d'=' -f2 | tr -d ' "')

    # Clean app_name for storage account (remove hyphens, lowercase)
    local clean_app_name=$(echo $app_name | tr -d '-' | tr '[:upper:]' '[:lower:]')
    local storage_name="st${clean_app_name}${environment}fn"

    # Check storage account name availability
    local storage_check=$(az storage account check-name --name "$storage_name" --query 'nameAvailable' -o tsv)
    if [ "$storage_check" = "true" ]; then
        print_status $GREEN "✓ Storage account name '$storage_name' is available"
    else
        print_status $RED "ERROR: Storage account name '$storage_name' is not available"
        print_status $YELLOW "Consider changing the app_name or environment in terraform.tfvars"
    fi
}

# Generate cost estimation
estimate_costs() {
    print_status $YELLOW "Generating cost estimation..."

    print_status $YELLOW "Key cost components for this infrastructure:"
    echo "• App Service Environment v3: ~$400-800/month (depending on region and usage)"
    echo "• App Service Plan (I1v2): ~$150/month per instance"
    echo "• Azure Function App: Consumption-based (included in ASE)"
    echo "• Storage Account: ~$10-20/month"
    echo "• Private Endpoints: ~$7/month per endpoint"
    echo "• Service Bus (Standard): ~$10/month + transactions"
    echo "• Key Vault: ~$3/month + operations"
    echo "• Application Insights: Usage-based pricing"
    echo
    print_status $YELLOW "Total estimated monthly cost: ~$600-900/month"
    print_status $YELLOW "Note: Actual costs may vary based on usage, region, and specific configurations"
}

# Clean up temporary files
cleanup() {
    print_status $YELLOW "Cleaning up temporary files..."
    rm -f tfplan
    rm -f .terraform.lock.hcl
    rm -rf .terraform/
    print_status $GREEN "✓ Cleanup completed"
}

# Main execution
main() {
    echo "Starting validation process..."
    echo

    check_tools
    check_azure_login
    validate_terraform
    plan_deployment
    validate_azure_resources
    estimate_costs

    echo
    print_status $GREEN "=== VALIDATION COMPLETED SUCCESSFULLY ==="
    print_status $GREEN "The infrastructure configuration is valid and ready for deployment"
    echo
    print_status $YELLOW "Next steps:"
    echo "1. Review the Terraform plan output above"
    echo "2. Adjust configuration if needed"
    echo "3. Run 'terraform apply' when ready to deploy"
    echo "4. Monitor the deployment (ASE v3 takes 60-90 minutes to deploy)"

    cleanup
}

# Trap for cleanup on exit
trap cleanup EXIT

# Run main function
main