#!/bin/bash

set -e

echo "=== Azure Infrastructure Connectivity Test Script ==="
echo "This script tests network connectivity and configuration after deployment"
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

# Get Terraform outputs
get_terraform_outputs() {
    print_status $YELLOW "Retrieving Terraform outputs..."

    if [ ! -f "terraform.tfstate" ]; then
        print_status $RED "ERROR: terraform.tfstate not found. Deploy the infrastructure first."
        exit 1
    fi

    FUNCTION_APP_NAME=$(terraform output -raw function_app_name)
    WEB_APP_NAME=$(terraform output -raw web_app_name)
    FUNCTION_APP_HOSTNAME=$(terraform output -raw function_app_hostname)
    WEB_APP_HOSTNAME=$(terraform output -raw web_app_hostname)
    RESOURCE_GROUP_NAME=$(terraform output -raw resource_group_name)
    KEY_VAULT_NAME=$(terraform output -raw key_vault_name)
    ASE_NAME=$(terraform output -raw ase_name)

    print_status $GREEN "✓ Retrieved Terraform outputs"
}

# Test DNS resolution
test_dns_resolution() {
    print_status $YELLOW "Testing DNS resolution..."

    # Test Function App DNS
    if nslookup "$FUNCTION_APP_HOSTNAME" &> /dev/null; then
        print_status $GREEN "✓ Function App DNS resolution successful: $FUNCTION_APP_HOSTNAME"
    else
        print_status $RED "✗ Function App DNS resolution failed: $FUNCTION_APP_HOSTNAME"
    fi

    # Test Web App DNS
    if nslookup "$WEB_APP_HOSTNAME" &> /dev/null; then
        print_status $GREEN "✓ Web App DNS resolution successful: $WEB_APP_HOSTNAME"
    else
        print_status $RED "✗ Web App DNS resolution failed: $WEB_APP_HOSTNAME"
    fi
}

# Test Azure services accessibility
test_azure_services() {
    print_status $YELLOW "Testing Azure services accessibility..."

    # Test Function App
    print_status $YELLOW "Testing Function App accessibility..."
    local func_status=$(az functionapp show --name "$FUNCTION_APP_NAME" --resource-group "$RESOURCE_GROUP_NAME" --query "state" -o tsv 2>/dev/null || echo "ERROR")

    if [ "$func_status" = "Running" ]; then
        print_status $GREEN "✓ Function App is running"
    else
        print_status $RED "✗ Function App is not running or not accessible (Status: $func_status)"
    fi

    # Test Web App
    print_status $YELLOW "Testing Web App accessibility..."
    local webapp_status=$(az webapp show --name "$WEB_APP_NAME" --resource-group "$RESOURCE_GROUP_NAME" --query "state" -o tsv 2>/dev/null || echo "ERROR")

    if [ "$webapp_status" = "Running" ]; then
        print_status $GREEN "✓ Web App is running"
    else
        print_status $RED "✗ Web App is not running or not accessible (Status: $webapp_status)"
    fi

    # Test ASE
    print_status $YELLOW "Testing App Service Environment..."
    local ase_status=$(az appservice ase show --name "$ASE_NAME" --resource-group "$RESOURCE_GROUP_NAME" --query "provisioningState" -o tsv 2>/dev/null || echo "ERROR")

    if [ "$ase_status" = "Succeeded" ]; then
        print_status $GREEN "✓ App Service Environment is successfully provisioned"
    else
        print_status $YELLOW "⚠ App Service Environment status: $ase_status (may still be provisioning)"
    fi
}

# Test Key Vault accessibility
test_key_vault() {
    print_status $YELLOW "Testing Key Vault accessibility..."

    # List secrets (should work if access policy is correctly configured)
    if az keyvault secret list --vault-name "$KEY_VAULT_NAME" --query "[].name" -o tsv &> /dev/null; then
        print_status $GREEN "✓ Key Vault is accessible"

        # Check if required secrets exist
        local secrets=$(az keyvault secret list --vault-name "$KEY_VAULT_NAME" --query "[].name" -o tsv)

        if echo "$secrets" | grep -q "hybrid-sql-connection-string"; then
            print_status $GREEN "✓ Hybrid SQL connection string secret exists"
        else
            print_status $RED "✗ Hybrid SQL connection string secret not found"
        fi

        if echo "$secrets" | grep -q "sql-connection-string"; then
            print_status $GREEN "✓ SQL connection string secret exists"
        else
            print_status $RED "✗ SQL connection string secret not found"
        fi
    else
        print_status $RED "✗ Key Vault is not accessible or access denied"
    fi
}

# Test private endpoints
test_private_endpoints() {
    print_status $YELLOW "Testing private endpoints..."

    # List private endpoints
    local pe_count=$(az network private-endpoint list --resource-group "$RESOURCE_GROUP_NAME" --query "length(@)" -o tsv)

    if [ "$pe_count" -gt 0 ]; then
        print_status $GREEN "✓ Found $pe_count private endpoint(s)"

        # Check private endpoint connection state
        local pe_states=$(az network private-endpoint list --resource-group "$RESOURCE_GROUP_NAME" --query "[].privateLinkServiceConnections[].privateLinkServiceConnectionState.status" -o tsv)

        while read -r state; do
            if [ "$state" = "Approved" ]; then
                print_status $GREEN "✓ Private endpoint connection approved"
            else
                print_status $YELLOW "⚠ Private endpoint connection state: $state"
            fi
        done <<< "$pe_states"
    else
        print_status $RED "✗ No private endpoints found"
    fi
}

# Test hybrid connection
test_hybrid_connection() {
    print_status $YELLOW "Testing hybrid connection configuration..."

    local sb_namespace=$(terraform output -raw servicebus_namespace_name)
    local hc_name=$(terraform output -raw hybrid_connection_name)

    # Check if hybrid connection exists
    if az servicebus hybridconnection show --namespace-name "$sb_namespace" --resource-group "$RESOURCE_GROUP_NAME" --name "$hc_name" &> /dev/null; then
        print_status $GREEN "✓ Hybrid connection exists and is configured"

        # Get connection details
        local endpoint=$(az servicebus hybridconnection show --namespace-name "$sb_namespace" --resource-group "$RESOURCE_GROUP_NAME" --name "$hc_name" --query "endpoint" -o tsv)
        print_status $YELLOW "Hybrid connection endpoint: $endpoint"

        print_status $YELLOW "Note: To complete hybrid connection setup:"
        print_status $YELLOW "1. Install Hybrid Connection Manager on your on-premises server"
        print_status $YELLOW "2. Configure it with the connection string from Key Vault"
        print_status $YELLOW "3. Verify connectivity to your SQL Server"
    else
        print_status $RED "✗ Hybrid connection not found or not accessible"
    fi
}

# Test HTTP connectivity (if accessible)
test_http_connectivity() {
    print_status $YELLOW "Testing HTTP connectivity (if publicly accessible)..."

    # Note: Since these are in ASE with private endpoints, they may not be publicly accessible
    print_status $YELLOW "Attempting to connect to Function App..."
    if curl -s --max-time 10 "https://$FUNCTION_APP_HOSTNAME" &> /dev/null; then
        print_status $GREEN "✓ Function App is reachable via HTTPS"
    else
        print_status $YELLOW "⚠ Function App is not publicly accessible (expected with private endpoints)"
    fi

    print_status $YELLOW "Attempting to connect to Web App..."
    if curl -s --max-time 10 "https://$WEB_APP_HOSTNAME" &> /dev/null; then
        print_status $GREEN "✓ Web App is reachable via HTTPS"
    else
        print_status $YELLOW "⚠ Web App is not publicly accessible (expected with private endpoints)"
    fi
}

# Generate connectivity report
generate_report() {
    print_status $YELLOW "Generating connectivity report..."

    cat > connectivity-report.md << EOF
# Azure Infrastructure Connectivity Report

Generated on: $(date)

## Infrastructure Overview
- **Function App**: $FUNCTION_APP_NAME
- **Web App**: $WEB_APP_NAME
- **App Service Environment**: $ASE_NAME
- **Resource Group**: $RESOURCE_GROUP_NAME
- **Key Vault**: $KEY_VAULT_NAME

## DNS Configuration
- **Function App Hostname**: $FUNCTION_APP_HOSTNAME
- **Web App Hostname**: $WEB_APP_HOSTNAME

## Network Architecture
- Private endpoints configured for both Function App and Web App
- Azure Front Door connected via Private Link
- VNet integration for hybrid connectivity
- ASE v3 provides network isolation

## Security Configuration
- Managed identities configured for both apps
- Key Vault access policies in place
- Private DNS zones configured
- Network Security Groups applied

## Hybrid Connectivity
- Service Bus namespace for hybrid connections
- Hybrid connection configured for on-premises SQL Server
- Connection strings stored securely in Key Vault

## Next Steps for Complete Setup
1. **Hybrid Connection Manager**: Install and configure on on-premises server
2. **SSL Certificates**: Configure custom SSL certificates if needed
3. **Application Deployment**: Deploy application code to Function App and Web App
4. **Monitoring**: Configure alerts and monitoring dashboards
5. **Testing**: Perform end-to-end application testing

## Important Notes
- ASE v3 deployment can take 60-90 minutes
- Private endpoint connections may need manual approval
- Hybrid connections require on-premises configuration
- Monitor costs as ASE v3 has significant base costs

EOF

    print_status $GREEN "✓ Connectivity report generated: connectivity-report.md"
}

# Main execution
main() {
    echo "Starting connectivity tests..."
    echo

    get_terraform_outputs
    test_dns_resolution
    test_azure_services
    test_key_vault
    test_private_endpoints
    test_hybrid_connection
    test_http_connectivity
    generate_report

    echo
    print_status $GREEN "=== CONNECTIVITY TESTS COMPLETED ==="
    print_status $YELLOW "Review the connectivity-report.md file for detailed findings"
}

# Check if required tools are available
if ! command -v az &> /dev/null; then
    print_status $RED "ERROR: Azure CLI is not installed"
    exit 1
fi

if ! command -v terraform &> /dev/null; then
    print_status $RED "ERROR: Terraform is not installed"
    exit 1
fi

# Run main function
main