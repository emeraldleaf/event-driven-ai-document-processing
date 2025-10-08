# Project Structure - Document Processing System

## 📁 Clean, Minimal Infrastructure

This project has been streamlined to **only include what's necessary** for a document processing system with Claude AI.

## File Structure

```
/infra
│
├── 📄 Infrastructure (Terraform)
│   ├── main.tf                     # Core: Resource group, VNet, subnets
│   ├── variables.tf                # Configuration variables
│   ├── outputs.tf                  # Output values and quick start commands
│   │
│   ├── document-storage.tf         # Document blob storage + Event Grid
│   ├── document-functions.tf       # Azure Functions for processing
│   ├── key-vault.tf                # Secrets (Anthropic API key)
│   ├── cosmos-db.tf                # Database (extended for documents)
│   ├── service-bus.tf              # Message queues (extended for documents)
│   └── event-grid.tf               # Event triggers
│
├── 📚 Documentation
│   ├── QUICKSTART.md               # ⭐ START HERE - 5-minute setup
│   ├── DOCUMENT_PROCESSING_GUIDE.md # Complete technical guide
│   ├── DEPLOYMENT_SUMMARY.md        # What was built
│   ├── PROJECT_STRUCTURE.md         # This file
│   ├── ARCHITECTURE.md              # System architecture
│   └── README.md                    # Original project README
│
├── 🐍 Application Code
│   ├── src/functions/               # Azure Functions (Python 3.11)
│   │   ├── function_app.py         # Main function definitions
│   │   ├── requirements.txt        # Python dependencies
│   │   ├── host.json               # Function runtime config
│   │   ├── local.settings.json     # Local dev settings
│   │   ├── services/
│   │   │   ├── claude_service.py   # Claude AI integration
│   │   │   ├── cosmos_service.py   # Cosmos DB operations
│   │   │   └── storage_service.py  # Blob storage operations
│   │   └── utils/
│   │       └── config.py           # Configuration management
│   │
│   └── src/web/                    # React Web UI
│       ├── package.json
│       ├── Dockerfile
│       ├── src/
│       │   ├── App.js              # Main UI component
│       │   ├── App.css             # Styling
│       │   ├── index.js
│       │   └── index.css
│       └── public/
│           └── index.html
│
├── 🛠️ Local Development
│   ├── docker-compose.local.yml    # Local emulators (Azurite, Cosmos)
│   ├── .env.example                # Environment template
│   └── scripts/
│       ├── setup-local.sh          # Automated setup
│       ├── setup-cosmos.py         # Cosmos DB initialization
│       └── setup-storage.py        # Blob storage initialization
│
└── ⚙️ Configuration
    ├── terraform.tfvars.example    # Terraform config template
    └── .gitignore
```

## 🎯 What Each Terraform File Does

### Core Infrastructure
- **main.tf** - Creates resource group, virtual network, subnets
- **variables.tf** - Defines all configuration options
- **outputs.tf** - Exports URLs and connection info

### Document Processing (New)
- **document-storage.tf** - Blob storage containers + Event Grid triggers
- **document-functions.tf** - Azure Functions app with Claude integration
- **key-vault.tf** - Secure storage for API keys and secrets

### Supporting Services (Extended)
- **cosmos-db.tf** - NoSQL database (extended with Documents, ExtractedData, Jobs containers)
- **service-bus.tf** - Message queues (extended with document-processing queue)
- **event-grid.tf** - Event routing for blob uploads

## 🗑️ What Was Removed

**Unnecessary Enterprise Infrastructure:**
- ❌ App Service Environment (ase.tf) - Too expensive for POC
- ❌ Old web apps (app-services.tf) - Using Functions instead
- ❌ Disaster Recovery (disaster-recovery.tf) - Overkill for POC
- ❌ Event Hubs (event-hubs.tf) - Not needed for basic processing
- ❌ Front Door (front-door.tf) - CDN not needed for POC
- ❌ Hybrid Connections (hybrid-connection.tf) - No on-prem connectivity
- ❌ Logic Apps (logic-apps.tf) - Not using workflow orchestration
- ❌ Management VMs (management.tf) - Not needed
- ❌ Advanced monitoring (monitoring-alerts.tf) - Optional for POC
- ❌ Private Endpoints (private-endpoints.tf) - Included in production mode
- ❌ Redis Cache (redis-cache.tf) - Not needed for document processing
- ❌ Resilience Policies (resilience-policies.tf) - Optional

**Old Files:**
- ❌ C# files (EmailService.cs, EmailServiceTests.cs)
- ❌ Validation scripts (validate.sh, terraform-syntax-check.sh, etc.)

## 💡 Key Design Decisions

### Minimal but Production-Ready
- Only essential Azure services
- Cost-optimized for POC (~$60/month)
- Can scale to production by setting `enable_cost_optimization = false`

### Event-Driven Architecture
- Event Grid triggers on blob upload
- Service Bus for reliable processing
- Cosmos DB for structured data storage
- Azure Functions for serverless compute

### Claude AI Integration
- Uses Anthropic API directly (simpler than Azure AI)
- Flexible extraction with natural language prompts
- Superior accuracy for varied document types
- Cost-effective (~$0.01 per document)

### Local Development First
- Full Docker-based local environment
- No Azure required for development
- Mock AI mode for testing without costs
- Fast iteration and debugging

## 📊 Resource Count

**Total Terraform Resources: ~30-40**
- Storage Accounts: 2 (documents, functions)
- Function Apps: 1 (document processor)
- Cosmos DB: 1 account, 1 database, 4 containers
- Service Bus: 1 namespace, 3 queues
- Event Grid: 1 system topic, 1 subscription
- Key Vault: 1 vault, 4 secrets
- Networking: 1 VNet, 3 subnets
- Monitoring: Application Insights

**Compare to original:** Reduced from ~100+ resources to ~40 essential resources.

## 💰 Cost Breakdown (POC Mode)

**Monthly Azure Costs:**
| Service | SKU | Cost |
|---------|-----|------|
| Functions | Consumption (Y1) | $0-5 |
| Cosmos DB | Serverless | $25 |
| Service Bus | Standard | $10 |
| Blob Storage | LRS, Hot | $5 |
| Event Grid | Pay per event | $1 |
| Key Vault | Standard | $1 |
| Application Insights | Basic | $5 |
| **Total Azure** | | **~$50/month** |

**Claude AI Costs:**
- ~$0.01 per document
- 1000 documents = ~$10

**Total POC: ~$60-70/month**

## 🚀 Getting Started

### Fastest Path (Local Development)
```bash
# 1. Read the quick start
cat QUICKSTART.md

# 2. Setup environment
cp .env.example .env
# Edit .env: set ENABLE_MOCK_AI=true

# 3. Run setup
./scripts/setup-local.sh

# 4. Start Functions (Terminal 1)
cd src/functions && func start

# 5. Start Web UI (Terminal 2)
cd src/web && npm start

# 6. Open http://localhost:3000
```

### Azure Deployment
```bash
# 1. Configure
cp terraform.tfvars.example terraform.tfvars
# Edit with your settings

# 2. Deploy
terraform init
terraform plan
terraform apply

# 3. Deploy code
cd src/functions
func azure functionapp publish $(terraform output -raw document_function_app_name)
```

## 🎯 What This System Does

**Input:** PDF, PNG, JPG, TIFF documents
**Process:** Claude AI extracts structured data
**Output:** JSON with extracted fields stored in Cosmos DB

**Example Use Cases:**
- Invoice processing (vendor, line items, totals)
- Receipt digitization (merchant, items, amounts)
- Form processing (fields, signatures, dates)
- Document classification and data extraction

## 🔍 Where to Look for Specific Features

**Want to customize extraction?**
→ `src/functions/services/claude_service.py`

**Want to add new document types?**
→ Edit the Claude prompt in `claude_service.py`

**Want to change storage policies?**
→ `document-storage.tf` (lifecycle rules, retention)

**Want to adjust costs?**
→ `variables.tf` (set `enable_cost_optimization = true/false`)

**Want to add monitoring?**
→ Application Insights is already configured

**Want to scale for production?**
→ Set `enable_cost_optimization = false` in terraform.tfvars

## 📞 Support

**Getting Started:** Read [QUICKSTART.md](QUICKSTART.md)
**Full Documentation:** Read [DOCUMENT_PROCESSING_GUIDE.md](DOCUMENT_PROCESSING_GUIDE.md)
**Deployment Info:** Read [DEPLOYMENT_SUMMARY.md](DEPLOYMENT_SUMMARY.md)
**Architecture:** Read [ARCHITECTURE.md](ARCHITECTURE.md)

---

**Status:** ✅ Clean, minimal, production-ready POC
**Version:** 1.0.0
**Last Updated:** 2025-10-07
