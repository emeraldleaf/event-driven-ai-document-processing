# Azure Enterprise Infrastructure

This repository contains Terraform Infrastructure as Code (IaC) for deploying a enterprise environment in Azure with the following components:

- **App Service Environment v3** (ASE v3) with zone redundancy
- **Azure Function App** (.NET 8 on Windows) with Key Vault integration
- **Azure App Service** (.NET 8 on Windows) for single-page applications
- **Private Endpoints** for all services (Function App, Web App, Key Vault)
- **Azure Front Door** with Web Application Firewall (WAF)
- **Azure Bastion** for secure management access
- **Management VM** with pre-installed Azure tools
- **Hybrid SQL Connection** to on-premises database via Service Bus
- **Network Security Groups** with HTTPS-only traffic

## Architecture Overview

```
Internet → Azure Front Door + WAF → Private Link → Virtual Network
                    ↓ (Blocks malicious traffic)
         
Virtual Network (10.0.0.0/16) - PCI DSS Compliant
├─ ASE v3 Subnet (10.0.1.0/24) - Zone Redundant
│  └─ App Service Environment v3
│     ├─ Function App (.NET 8) → Elastic Premium (EP1) - Dynamic Scaling
│     └─ Web App (.NET 8) → Dedicated (I1v2) - Single Page Application
│
├─ Private Endpoints Subnet (10.0.2.0/24) - HTTPS Only
│  ├─ Function App Private Endpoint
│  ├─ Web App Private Endpoint  
│  └─ Key Vault Private Endpoint
│
├─ Hybrid Subnet (10.0.3.0/24)
│  └─ Service Bus Hybrid Connection → On-Prem SQL
│
├─ Azure Bastion Subnet (10.0.4.0/26)
│  └─ Azure Bastion (Secure Management Access)
│
└─ Management Subnet (10.0.5.0/24)
   └─ Management VM (Windows Server 2022 + Azure Tools)
```

## 🔒 PCI DSS Compliance Features

- **Network Isolation**: All services use private endpoints, no public access
- **Encryption**: TLS 1.2+ enforced, internal encryption enabled
- **Web Application Firewall**: OWASP Core Rule Set, bot protection, rate limiting
- **Access Control**: Managed identities, Key Vault integration, NSG rules
- **Audit Logging**: Azure Bastion access logs, Key Vault audit trails
- **Secure Management**: No direct VM access, browser-based Bastion connection

## 🚀 Hybrid Hosting Architecture Benefits

**Elastic Premium for Functions (EP1)**:
- ✅ **Dynamic Auto-Scaling**: Automatically scales based on demand (0-20 instances)
- ✅ **No Cold Starts**: Pre-warmed instances ensure immediate response
- ✅ **Cost Efficiency**: Pay for actual usage with minimum baseline
- ✅ **VNet Integration**: Full network isolation within ASE v3
- ✅ **Zone Redundancy**: High availability across availability zones

**Dedicated for Web App (I1v2)**:
- ✅ **Predictable Performance**: Fixed resources for consistent SPA delivery
- ✅ **Simple Management**: No complex scaling configuration needed
- ✅ **Cost Predictability**: Fixed monthly cost regardless of traffic
- ✅ **ASE Integration**: Full network isolation and security
- ✅ **Optimal for SPAs**: Right-sized for static content serving

## Prerequisites

1. **Azure CLI** installed and configured
2. **Terraform** >= 1.0 installed
3. **Azure subscription** with appropriate permissions
4. **Existing Azure Front Door** resource
5. **On-premises SQL Server** accessible for hybrid connection

## Quick Start

### 1. Configure Variables

Copy the example variables file and update with your values:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your specific configuration:

```hcl
# Basic Configuration
location    = "East US 2"
environment = "dr"
app_name    = "myapp"

# Azure Front Door Configuration (REQUIRED)
existing_front_door_id = "/subscriptions/YOUR-SUBSCRIPTION-ID/resourceGroups/YOUR-RG/providers/Microsoft.Cdn/profiles/YOUR-FRONT-DOOR-NAME"

# On-premises SQL Server Configuration
on_prem_sql_server = {
  server_name   = "your-sql-server.company.local"
  database_name = "YourDatabase"
  port          = 1433
}

# Management VM Configuration (REQUIRED for PCI compliance)
management_vm_admin_password = "YourSecurePassword123!"  # Minimum 12 characters
```

### 2. Validate Configuration

Run the validation script to check your configuration without deploying:

```bash
chmod +x validate.sh
./validate.sh
```

This script will:
- Validate Terraform syntax and formatting
- Check Azure CLI authentication
- Verify resource name availability
- Create a deployment plan (dry run)
- Estimate costs
- Validate Azure Front Door accessibility

### 3. Deploy Infrastructure

If validation passes, deploy the infrastructure:

```bash
# Initialize Terraform
terraform init

# Plan deployment
terraform plan

# Apply configuration (this will take 60-90 minutes due to ASE v3)
terraform apply
```

### 4. Test Connectivity

After deployment, run the connectivity test script:

```bash
chmod +x test-connectivity.sh
./test-connectivity.sh
```

This will generate a detailed connectivity report.

## Key Components

### App Service Environment v3 (Zone Redundant)
- **Internal Load Balancer**: Web and Publishing endpoints
- **Network Isolation**: Complete isolation within VNet
- **Zone Redundancy**: High availability across availability zones
- **Security**: TLS 1.0 disabled, internal encryption enabled
- **Custom Domain**: ASE-specific DNS suffix for private access

### Web Application Firewall (WAF)
- **OWASP Core Rule Set v2.1**: SQL injection and XSS protection
- **Bot Protection**: Microsoft Bot Manager Rule Set
- **Rate Limiting**: DDoS protection (100 req/min per IP)
- **Custom Rules**: Geo-blocking capability (configurable)
- **Prevention Mode**: Blocks malicious traffic automatically

### Hybrid Hosting Architecture
- **Function App**: Elastic Premium (EP1) plan for dynamic scaling and cold start elimination
- **Web App**: Dedicated (I1v2) plan for consistent SPA hosting performance
- **Best of Both**: Functions get elastic scaling, Web App gets predictable resources
- **Zone Redundancy**: Both plans support zone redundancy within ASE v3
- **Cost Optimization**: Right-sized hosting plans for each workload type

### Private Endpoints & Network Security
- **Function App**: Private endpoint with managed identity Key Vault access
- **Web App**: Private endpoint for SPA hosting
- **Key Vault**: Private endpoint for PCI compliance
- **DNS Integration**: Private DNS zones for all services
- **NSG Rules**: HTTPS-only traffic, explicit deny-all rules

### Azure Bastion & Management
- **Secure Access**: Browser-based RDP without public IPs
- **Management VM**: Windows Server 2022 with Azure tools pre-installed
- **MFA Integration**: Built-in multi-factor authentication
- **Audit Logging**: Complete access audit trail for compliance
- **File Transfer**: Secure file copy capabilities

### Hybrid Connectivity & Security
- **Service Bus**: Standard tier for hybrid SQL connections
- **Key Vault**: Private endpoint, public access disabled
- **Managed Identity**: Function App secure access to secrets
- **Connection Strings**: Encrypted storage with 90-day retention
- **Purge Protection**: Prevents accidental secret deletion

## 💰 Cost Considerations (PCI Compliant Architecture)

Estimated monthly costs (varies by region and usage):

### Core Infrastructure
- **ASE v3 (Zone Redundant)**: $800-1200/month (base cost + zone redundancy)
- **Function App - Elastic Premium (EP1)**: ~$180/month (dynamic scaling)
- **Web App - Dedicated (I1v2)**: ~$150/month (predictable performance)
- **Storage Account**: ~$15/month (with diagnostics)

### Security & Management  
- **Azure Bastion (Standard)**: ~$140/month (24/7 availability)
- **Management VM (Standard_B2s)**: ~$60/month
- **WAF Policy**: ~$5/month + request charges
- **Private Endpoints**: ~$21/month (3 endpoints × $7)

### Data & Connectivity
- **Service Bus Standard**: ~$10/month + transactions  
- **Key Vault (Standard)**: ~$3/month + operations
- **Public IP (Bastion)**: ~$4/month

**Total estimated**: $1,200-1,500/month
*Premium cost for enterprise-grade PCI compliance and security*

## ⏱️ Deployment Timeline

1. **Networking (VNet, Subnets, NSGs)**: ~10 minutes
2. **App Service Environment v3 (Zone Redundant)**: **90-120 minutes** ⏰
3. **Service Plans (Elastic Premium + Dedicated)**: ~10 minutes
4. **Function App & Web App**: ~15 minutes
4. **Private Endpoints & DNS**: ~15 minutes
5. **Azure Bastion**: ~10 minutes
6. **Management VM & Tools**: ~15 minutes
7. **Key Vault & Service Bus**: ~10 minutes
8. **WAF Policy**: ~5 minutes

**Total deployment time**: 2-3 hours (due to zone redundant ASE)

## Post-Deployment Setup

### 1. Hybrid Connection Manager
Install on your on-premises server that has access to SQL Server:

1. Download Hybrid Connection Manager from Azure portal
2. Configure with connection string from Key Vault
3. Verify connectivity to SQL Server

### 2. Application Deployment
Deploy your .NET 8 applications:

```bash
# Function App
func azure functionapp publish func-myapp-dr

# Web App
az webapp deployment source config-zip \
  --resource-group rg-myapp-dr \
  --name app-myapp-dr \
  --src app.zip
```

### 3. Management Access Setup
Access your infrastructure securely:

1. **Azure Portal** → Navigate to your resource group
2. **Azure Bastion** → Connect to management VM
3. **Management VM** has pre-installed tools:
   - Azure PowerShell modules
   - Azure CLI
   - RSAT tools for AD management
   - Visual Studio Code (optional)

### 4. WAF Policy Verification
The WAF policy is automatically associated with your Front Door endpoints. Verify in Azure Portal:
- Front Door → Security → Web Application Firewall
- Confirm policy association with Function App and Web App origins

## 🔍 Monitoring and Maintenance

### Security Monitoring
- **Application Insights**: Performance and dependency tracking
- **Azure Bastion Logs**: Administrative access audit trail  
- **Key Vault Logs**: Secret access monitoring
- **WAF Logs**: Blocked request analysis
- **NSG Flow Logs**: Network traffic analysis (optional)

### Health Checks & Endpoints
Configure application health endpoints:
- Function App: `/api/health`
- Web App: `/health`  
- Management VM: RDP via Bastion only

### Backup and Recovery
- **App Service**: Automatic backup configured
- **Key Vault**: 90-day soft delete + purge protection
- **Management VM**: Boot diagnostics enabled
- **Infrastructure**: Terraform state backup recommended
- **Database**: Backup via hybrid connection

## 🔧 Troubleshooting

### Common Issues

1. **ASE v3 Deployment Timeout**
   - Zone redundant ASE can take 2-3 hours
   - Monitor deployment status in Azure portal
   - Check subnet delegation is configured correctly

2. **Private Endpoint Connection Issues**
   - Verify private DNS zone configuration
   - Check NSG rules allow HTTPS traffic
   - Ensure Key Vault network ACLs are configured properly

3. **Azure Bastion Connection Problems**
   - Verify Bastion subnet is exactly named "AzureBastionSubnet"
   - Check Bastion subnet size is minimum /26
   - Ensure management VM is in allowed subnet

4. **WAF Blocking Legitimate Traffic**
   - Review WAF logs in Azure portal
   - Adjust custom rules if needed
   - Consider rule exclusions for false positives

5. **Management VM Access Issues**
   - Use Azure Bastion, not direct RDP
   - Verify NSG allows traffic from Bastion subnet
   - Check VM managed identity permissions

6. **Key Vault Access Denied**
   - Verify Function App managed identity has access policy
   - Check Key Vault private endpoint DNS resolution
   - Ensure network ACLs allow VNet access

7. **Hybrid Connection Problems**
   - Install Hybrid Connection Manager on on-premises server
   - Verify Service Bus connection string
   - Check firewall settings for outbound HTTPS (443)

### Useful Commands

```bash
# Check deployment status
terraform show

# View outputs
terraform output

# Destroy infrastructure (use with caution)
terraform destroy

# Format Terraform files
terraform fmt

# Validate configuration
terraform validate
```

## 🔐 Security Best Practices (PCI DSS Compliant)

### 1. Network Security (PCI DSS Requirements 1.2, 1.3)
- **Complete Network Isolation**: All services use private endpoints
- **Zero Public Access**: No direct internet access to applications  
- **HTTPS-Only Traffic**: NSG rules block HTTP, allow HTTPS only
- **Network Segmentation**: Dedicated subnets for different functions
- **WAF Protection**: OWASP rules block injection attacks and XSS

### 2. Identity and Access Management (PCI DSS Requirements 7, 8)
- **Managed Identities**: No stored credentials, Azure AD authentication
- **Least Privilege**: Function App has minimal Key Vault permissions
- **Secure Management**: Azure Bastion for administrative access only
- **MFA Enforcement**: Built-in multi-factor authentication via Bastion
- **Individual Accountability**: Audit trails for all administrative actions

### 3. Data Protection (PCI DSS Requirements 3, 4)
- **Encryption in Transit**: TLS 1.2+ enforced across all connections
- **Encryption at Rest**: Azure platform encryption for all storage
- **Key Management**: Azure Key Vault with private endpoints
- **Secret Protection**: 90-day retention, purge protection enabled
- **Secure Connections**: Private hybrid connections to on-premises SQL

### 4. Monitoring and Logging (PCI DSS Requirements 10, 11)
- **Access Logging**: Azure Bastion logs all administrative sessions
- **Security Monitoring**: WAF logs blocked attacks and threats
- **Key Vault Auditing**: All secret access attempts logged
- **Network Monitoring**: NSG flow logs available (enable if required)
- **Application Insights**: Performance and security event tracking

### 5. Vulnerability Management (PCI DSS Requirements 6, 11.2)
- **WAF Protection**: Real-time blocking of OWASP Top 10 attacks
- **Automated Patching**: Azure platform handles infrastructure updates
- **Secure Development**: Private endpoints prevent data exposure
- **Regular Updates**: Management VM configured for Windows updates

## Support and Contributing

For issues and questions:
1. Check the troubleshooting section
2. Review Azure documentation for specific services
3. Check Terraform provider documentation

## License

This infrastructure code is provided as-is for all purposes.
