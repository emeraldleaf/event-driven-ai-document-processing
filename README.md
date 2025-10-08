# Document Processing System with Claude AI

**Enterprise-grade, event-driven document processing system** that extracts structured data from documents using Claude AI and Azure cloud services.

[![Code Quality](https://img.shields.io/badge/Code%20Quality-A%20(9%2F10)-brightgreen)](CODACY_ANALYSIS_REPORT.md)
[![Complexity](https://img.shields.io/badge/Complexity-2.3%20CCN-brightgreen)](CODACY_ANALYSIS_REPORT.md)
[![Security](https://img.shields.io/badge/Security-Patched-green)](SECURITY_FIXES.md)

---

## 🎯 What This System Does

**Upload a document** (PDF, image) → **AI extracts structured data** → **Results stored in database**

- **Handles**: Invoices, receipts, forms, any document with structured data
- **Extracts**: Vendor info, line items, totals, dates, custom fields
- **Scales**: Automatically handles high-volume processing
- **Cost**: ~$60/month for POC, ~$0.01 per document

---

## 🏗️ Architecture

```
┌─────────────┐
│   Upload    │ User uploads document via web UI
└──────┬──────┘
       │
       ▼
┌─────────────────────────────┐
│   Blob Storage (incoming)   │ Event Source - triggers processing
└──────┬──────────────────────┘
       │ BlobCreated Event
       ▼
┌─────────────────────────────┐
│      Event Grid             │ Event Router - decouples components
└──────┬──────────────────────┘
       │
       ▼
┌─────────────────────────────┐
│    Service Bus Queue        │ Message Buffer - ensures delivery
│  • Guaranteed delivery      │ • Handles traffic spikes
│  • Dead letter queue        │ • Auto-retry on failure
└──────┬──────────────────────┘
       │ Queue Trigger
       ▼
┌─────────────────────────────┐
│    Azure Function           │ Event Consumer - processes documents
│  • Auto-scales (1-200)      │ • Calls Claude AI
│  • Serverless compute       │ • Stateless design
└──────┬──────────────────────┘
       │
       ├──▶ Claude AI (Anthropic) - Extracts structured data
       │
       ├──▶ Cosmos DB - Stores metadata + extracted data
       │
       └──▶ Service Bus - Publishes completion events
```

### **Distributed Systems Patterns**
- ✅ Event-driven architecture
- ✅ Horizontal auto-scaling
- ✅ Stateless services
- ✅ At-least-once delivery
- ✅ Retry with exponential backoff
- ✅ Dead letter queues
- ✅ Polyglot persistence

**[Read full architecture guide →](DISTRIBUTED_SYSTEMS_PATTERNS.md)**

---

## 🚀 Quick Start

### Option 1: Local Development (5 minutes)

**No Azure account needed!**

```bash
# 1. Copy environment template
cp .env.example .env

# 2. Edit .env - Set ENABLE_MOCK_AI=true for testing without API key
vim .env

# 3. Run setup script
./scripts/setup-local.sh

# 4. Start Azure Functions (Terminal 1)
cd src/functions
source .venv/bin/activate
func start

# 5. Start Web UI (Terminal 2)
cd src/web
npm install
npm start

# 6. Open http://localhost:3000
# Upload documents and see them processed!
```

**[Detailed local setup guide →](QUICKSTART.md)**

---

### Option 2: Deploy to Azure

```bash
# 1. Configure deployment
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your settings

# 2. Deploy infrastructure (~15 minutes)
terraform init
terraform plan
terraform apply

# 3. Deploy function code
cd src/functions
func azure functionapp publish $(terraform output -raw document_function_app_name)

# 4. Deploy web UI
cd src/web
npm run build
az storage blob upload-batch \
  --account-name $(terraform output -raw document_storage_account_name) \
  --destination '$web' \
  --source build/

# 5. Get your URLs
terraform output quick_start_azure
```

**[Full deployment guide →](DOCUMENT_PROCESSING_GUIDE.md)**

---

## 💡 Features

### 🤖 **AI-Powered Extraction**
- **Claude 3.5 Sonnet** for superior accuracy
- Handles invoices, receipts, forms, general documents
- Extracts vendor info, line items, totals, dates, custom fields
- Confidence scoring and validation
- Natural language prompts (easily customizable)

### ⚡ **Event-Driven Architecture**
- Blob upload triggers automatic processing
- Event Grid → Service Bus → Azure Functions
- Decoupled components for independent scaling
- Guaranteed message delivery
- Automatic retry on failures

### 📈 **High-Volume Scalability**
- Auto-scales to 200+ function instances
- Processes thousands of documents/hour
- Queue buffering handles traffic spikes
- Partitioned data storage (Cosmos DB)
- Zero dropped documents

### 🛡️ **Enterprise-Ready**
- Comprehensive error handling
- Dead letter queues for failed messages
- Complete audit trail
- Monitoring with Application Insights
- Security: Managed identities, Key Vault, TLS 1.2+

### 💰 **Cost-Optimized**
- **POC Mode**: ~$60/month
  - Consumption Functions (serverless)
  - Serverless Cosmos DB
  - Mock AI for testing (no API costs)
- **Production Mode**: ~$200-400/month
  - Premium Functions with VNet
  - Provisioned Cosmos DB
  - Multi-region replication
- **Claude AI**: ~$0.01 per document

### 🧪 **Local Development**
- Full Docker-based environment
- Azurite (storage emulator)
- Cosmos DB emulator
- Mock AI mode (test without costs)
- Hot reload for fast iteration

---

## 📊 What Gets Extracted

### Sample Invoice → Structured JSON

```json
{
  "document_type": "invoice",
  "vendor": {
    "name": "Acme Corp",
    "address": "123 Main St, Anytown, USA",
    "tax_id": "12-3456789"
  },
  "invoice_number": "INV-2024-001",
  "date": "2024-01-15",
  "line_items": [
    {
      "description": "Professional Services",
      "quantity": 10.0,
      "unit_price": 150.00,
      "total": 1500.00
    }
  ],
  "subtotal": 1500.00,
  "tax": 150.00,
  "total": 1650.00,
  "currency": "USD",
  "confidence": 0.95
}
```

**Supports:**
- Invoices & receipts (vendor, items, totals)
- Forms & applications (fields, signatures)
- General documents (entities, tables, summaries)
- Custom document types (modify prompt)

---

## 📁 Project Structure

```
/infra
├── 📄 Infrastructure (Terraform)
│   ├── main.tf                     # Core resources
│   ├── document-storage.tf         # Blob storage + Event Grid
│   ├── document-functions.tf       # Azure Functions
│   ├── key-vault.tf                # Secrets management
│   ├── cosmos-db.tf                # Database
│   ├── service-bus.tf              # Message queues
│   └── event-grid.tf               # Event routing
│
├── 🐍 Application Code
│   ├── src/functions/               # Azure Functions (Python 3.11)
│   │   ├── function_app.py         # Event handlers
│   │   └── services/
│   │       ├── claude_service.py   # AI integration
│   │       ├── cosmos_service.py   # Database operations
│   │       └── storage_service.py  # Blob & messaging
│   │
│   └── src/web/                    # React Web UI
│       ├── src/App.js              # Document upload interface
│       └── package.json
│
├── 🐳 Local Development
│   ├── docker-compose.local.yml    # Emulators (Azurite, Cosmos)
│   ├── scripts/setup-local.sh      # Automated setup
│   └── .env.example                # Configuration template
│
└── 📚 Documentation
    ├── README.md                   # This file
    ├── QUICKSTART.md               # Get started in 5 min
    ├── DOCUMENT_PROCESSING_GUIDE.md # Complete guide
    ├── DISTRIBUTED_SYSTEMS_PATTERNS.md # Architecture patterns
    ├── DEPLOYMENT_SUMMARY.md        # What was built
    ├── CODACY_ANALYSIS_REPORT.md    # Code quality report
    └── SECURITY_FIXES.md            # Security updates
```

---

## 🎓 Learning & Demonstration

This codebase is **designed to demonstrate enterprise-grade distributed systems patterns**.

### Code Quality
- ✅ **Grade A (9/10)** on Codacy analysis
- ✅ **Average complexity: 2.3** (excellent maintainability)
- ✅ **Zero code smells** detected
- ✅ **All security vulnerabilities patched**

### Patterns Demonstrated
1. **Event-Driven Architecture** - Complete event flow with Event Grid, Service Bus, Functions
2. **Horizontal Scaling** - Stateless services, auto-scaling, partitioned data
3. **Resilience** - Retry logic, dead letter queues, circuit breakers
4. **Observability** - Structured logging, distributed tracing, metrics
5. **Polyglot Persistence** - Blob Storage (content), Cosmos DB (metadata), Service Bus (events)

### Documentation
- 📖 **50%+ code comments** explaining WHY, not just WHAT
- 📖 **Distributed systems patterns guide** with diagrams
- 📖 **Complete architecture documentation**
- 📖 **Local development setup**
- 📖 **Production deployment guide**

**[Read the patterns guide →](DISTRIBUTED_SYSTEMS_PATTERNS.md)**

---

## 🛠️ Technology Stack

### Azure Services
- **Azure Functions** (Python 3.11) - Serverless compute
- **Blob Storage** - Document storage with lifecycle management
- **Cosmos DB** - NoSQL database with global distribution
- **Service Bus** - Message queuing with guaranteed delivery
- **Event Grid** - Event routing and distribution
- **Key Vault** - Secrets management
- **Application Insights** - Monitoring and analytics

### AI & Libraries
- **Claude 3.5 Sonnet** (Anthropic) - Document understanding
- **Python 3.11** - Azure Functions runtime
- **React 18** - Web UI
- **Terraform** - Infrastructure as Code

---

## 💰 Cost Breakdown

### POC/Development (~$60/month)
| Service | Cost |
|---------|------|
| Azure Functions (Consumption) | $0-5 |
| Cosmos DB (Serverless) | $25 |
| Service Bus (Standard) | $10 |
| Blob Storage (LRS) | $5 |
| Event Grid | $1 |
| Application Insights | $5 |
| **Azure Total** | **~$50** |
| Claude AI (1000 docs) | $10 |
| **Grand Total** | **~$60** |

### Production (~$400/month)
- Premium Functions with VNet: $150
- Provisioned Cosmos DB: $100
- Service Bus Premium: $50
- Geo-redundant storage: $20
- Other services: $80
- **Total: ~$400/month** + Claude API usage

**Cost Optimization Features:**
- Auto-archive old documents
- TTL for automatic cleanup
- Serverless/consumption pricing
- Local dev environment (no cloud costs)

---

## 📋 Prerequisites

### Local Development
- Python 3.11+
- Node.js 18+
- Docker Desktop
- Azure Functions Core Tools
- Anthropic API key (or use mock mode)

### Azure Deployment
- Azure subscription
- Azure CLI
- Terraform 1.0+
- Anthropic API key

---

## 🎬 Demo Script

**5-Minute Demo:**

1. **Show Architecture** (1 min)
   - Event-driven flow diagram
   - Explain auto-scaling and resilience

2. **Local Demo** (2 min)
   - Upload sample invoice via web UI
   - Show real-time processing status
   - Display extracted structured data

3. **Code Walkthrough** (1 min)
   - Show Claude service integration
   - Highlight distributed systems patterns
   - Point out comprehensive comments

4. **Quality & Scale** (1 min)
   - Codacy report (9/10 grade A)
   - Auto-scaling configuration
   - Cost optimization features

**15-Minute Deep Dive:**
Add: Terraform infrastructure, Cosmos DB partitioning, Service Bus guarantees, monitoring dashboards

---

## 🔧 Customization

### Change Extraction Schema
Edit `src/functions/services/claude_service.py`:
```python
def _get_extraction_prompt(self) -> str:
    return """Extract YOUR custom fields here..."""
```

### Adjust Processing Limits
Edit `variables.tf`:
```hcl
max_document_size_mb    = 100  # Default: 50
document_retention_days = 90   # Default: 30
```

### Add New Document Types
Update the Claude prompt with your schema:
```
For purchase orders, include:
- po_number
- vendor
- delivery_date
- line_items: [{sku, description, quantity, price}]
```

---

## 📊 Monitoring

### Local Development
- Function logs in terminal
- Web UI browser console
- Cosmos DB emulator explorer
- Azurite storage explorer

### Azure Production
- Application Insights dashboards
- Cosmos DB metrics
- Service Bus queue depths
- Blob storage analytics
- Custom alerts

---

## 🐛 Troubleshooting

### Local Development

**Cosmos DB won't start:**
```bash
# Increase Docker memory to 4GB
# Docker Desktop → Settings → Resources → Memory
```

**Function can't find modules:**
```bash
cd src/functions
source .venv/bin/activate
pip install -r requirements.txt
```

**Port 7071 already in use:**
```bash
lsof -i :7071
kill -9 <PID>
```

### Azure Deployment

**Function deployment fails:**
```bash
# Redeploy
func azure functionapp publish <name> --python
```

**Documents not processing:**
- Check Service Bus queue has messages
- Check Function App logs in Azure Portal
- Verify Event Grid subscription is active

---

## 🔐 Security

### Features
- ✅ Managed identities (no connection strings)
- ✅ Key Vault for secrets
- ✅ TLS 1.2+ everywhere
- ✅ Private endpoints (production mode)
- ✅ Network isolation
- ✅ All vulnerabilities patched

### Security Reports
- [Codacy Analysis Report](CODACY_ANALYSIS_REPORT.md)
- [Security Fixes Applied](SECURITY_FIXES.md)

---

## 📚 Documentation

| Document | Description |
|----------|-------------|
| [QUICKSTART.md](QUICKSTART.md) | ⭐ Start here - 5-minute setup |
| [DOCUMENT_PROCESSING_GUIDE.md](DOCUMENT_PROCESSING_GUIDE.md) | Complete technical guide |
| [DISTRIBUTED_SYSTEMS_PATTERNS.md](DISTRIBUTED_SYSTEMS_PATTERNS.md) | Architecture patterns explained |
| [DEPLOYMENT_SUMMARY.md](DEPLOYMENT_SUMMARY.md) | What was built and how to use it |
| [CODACY_ANALYSIS_REPORT.md](CODACY_ANALYSIS_REPORT.md) | Code quality analysis |
| [PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md) | File organization |

---

## 🤝 Support

**Getting Started:** Read [QUICKSTART.md](QUICKSTART.md)

**Issues:** Check troubleshooting section above

**Architecture Questions:** Read [DISTRIBUTED_SYSTEMS_PATTERNS.md](DISTRIBUTED_SYSTEMS_PATTERNS.md)

---

## 📄 License

This project is provided as-is for demonstration and educational purposes.

---

## 🎉 Quick Commands

```bash
# Local Development
./scripts/setup-local.sh        # Setup local environment
cd src/functions && func start  # Start Functions
cd src/web && npm start         # Start Web UI

# Azure Deployment
terraform apply                 # Deploy infrastructure
func azure functionapp publish <name>  # Deploy functions

# Testing
curl http://localhost:7071/api/health  # Health check
curl http://localhost:7071/api/documents  # List documents

# Monitoring
terraform output                # Show all URLs
./.codacy/cli.sh analyze       # Run code analysis
```

---

**Built with Azure + Claude AI • Event-Driven Architecture • Production-Ready**

🚀 **[Get Started in 5 Minutes →](QUICKSTART.md)**
