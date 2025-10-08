# Document Processing System with Claude AI

Enterprise-grade, event-driven document processing system that extracts structured data from documents using Claude AI, deployed on Azure with full local development support.

## 🎯 Overview

This system processes high-volume documents (PDFs, images) and extracts structured data using Claude's advanced AI capabilities. It's designed to be:

- **Enterprise-grade**: Built on Azure with event-driven architecture
- **Cost-optimized**: POC-friendly with configurable cost controls
- **Locally runnable**: Full local dev environment with Docker
- **Scalable**: Handles high-volume processing with auto-scaling
- **Resilient**: Dead letter queues, retries, and error handling

## 🏗️ Architecture

```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐
│   Upload    │────▶│ Blob Storage │────▶│ Event Grid  │
│   Web UI    │     │  (Incoming)  │     │   Trigger   │
└─────────────┘     └──────────────┘     └──────┬──────┘
                                                  │
                                                  ▼
                    ┌─────────────────────────────────────┐
                    │      Service Bus Queue               │
                    │   (document-processing)             │
                    └──────────────┬──────────────────────┘
                                   │
                                   ▼
                    ┌─────────────────────────────────────┐
                    │    Azure Function (Python)          │
                    │  ┌─────────────────────────────┐   │
                    │  │ 1. Download from Blob       │   │
                    │  │ 2. Call Claude API          │───┼──▶ Anthropic API
                    │  │ 3. Extract Structured Data  │   │
                    │  │ 4. Save to Cosmos DB        │   │
                    │  │ 5. Move to Processed        │   │
                    │  └─────────────────────────────┘   │
                    └──────────────┬──────────────────────┘
                                   │
                    ┌──────────────┴──────────────┬────────────────┐
                    ▼                             ▼                ▼
            ┌───────────────┐          ┌──────────────┐  ┌────────────┐
            │   Cosmos DB   │          │ Blob Storage │  │ Service Bus│
            │  - Documents  │          │  (Processed) │  │  Complete  │
            │  - Extracted  │          └──────────────┘  └────────────┘
            │  - Jobs       │
            └───────────────┘
```

## 📋 Features

### Document Processing
- **Multi-format support**: PDF, PNG, JPG, TIFF
- **Intelligent extraction**: Uses Claude 3.5 Sonnet for accurate data extraction
- **Flexible schemas**: Handles invoices, receipts, forms, and general documents
- **Validation**: Automatic field validation and confidence scoring

### Event-Driven Architecture
- **Event Grid**: Triggers on blob upload
- **Service Bus**: Reliable message queuing with dead letter queues
- **Event Hubs**: Optional analytics and audit trail
- **Auto-retry**: Automatic retry with exponential backoff

### Data Storage
- **Cosmos DB**: Document metadata and extracted data
- **Blob Storage**: Original and processed documents with lifecycle management
- **TTL policies**: Automatic data cleanup

### Local Development
- **Docker Compose**: Full local environment
- **Mock AI**: Test without API calls
- **Emulators**: Azurite (Storage) + Cosmos DB Emulator
- **Hot reload**: Live code updates

## 🚀 Quick Start

### Prerequisites

- Python 3.11+
- Node.js 18+
- Docker Desktop
- Azure Functions Core Tools
- Anthropic API key (or use mock mode)

### Local Development Setup

1. **Clone and setup**:
```bash
cd /Users/joshuadell/Dev/infra

# Copy environment variables
cp .env.example .env

# Edit .env and add your Anthropic API key
# Or set ENABLE_MOCK_AI=true for testing without API
vim .env
```

2. **Run setup script**:
```bash
chmod +x scripts/setup-local.sh
./scripts/setup-local.sh
```

3. **Start Azure Functions**:
```bash
cd src/functions
source .venv/bin/activate
func start
```

4. **Start Web UI** (in a new terminal):
```bash
cd src/web
npm install
npm start
```

5. **Open the application**:
- Web UI: http://localhost:3000
- Functions API: http://localhost:7071
- Azurite Explorer: http://localhost:10000

### Testing Locally

1. Open http://localhost:3000
2. Drag and drop a document (PDF or image)
3. Watch it process in real-time
4. Click "View Data" to see extracted fields

**Note**: With `ENABLE_MOCK_AI=true`, you'll get sample extracted data without making API calls.

## ☁️ Azure Deployment

### Prerequisites

- Azure subscription
- Terraform 1.0+
- Azure CLI logged in
- Anthropic API key

### Configuration

1. **Create terraform.tfvars**:
```hcl
location                     = "eastus2"
environment                  = "dev"  # or "production"
app_name                     = "docprocessor"
anthropic_api_key            = "sk-ant-xxxxx"
enable_cost_optimization     = true  # Use for POC
max_document_size_mb         = 50
document_retention_days      = 30

# If you have existing resources
existing_front_door_id       = "/subscriptions/.../frontDoorProfiles/..."
on_prem_sql_server = {
  server_name   = "sql.company.local"
  database_name = "AppDB"
  port          = 1433
}
management_vm_admin_password = "YourSecurePassword123!"
```

2. **Deploy infrastructure**:
```bash
# Initialize Terraform
terraform init

# Preview changes
terraform plan

# Deploy (takes ~10-15 minutes)
terraform apply
```

3. **Deploy function code**:
```bash
cd src/functions

# Create deployment package
func azure functionapp publish <function-app-name>
```

4. **Deploy web UI**:
```bash
cd src/web

# Build production bundle
npm run build

# Upload to static website storage
az storage blob upload-batch \
  --account-name <storage-account-name> \
  --destination '$web' \
  --source build/
```

### Post-Deployment

1. **Get function app URL**:
```bash
terraform output document_function_app_url
```

2. **Get storage static website URL**:
```bash
terraform output document_storage_static_website_url
```

3. **Test upload**:
```bash
curl -X POST \
  https://<function-app-url>/api/upload \
  -F "file=@sample-invoice.pdf"
```

## 💰 Cost Optimization (POC Mode)

When `enable_cost_optimization = true`:

### Azure Costs (POC/Dev)
- **Functions**: Consumption Plan (~$0/month for low volume)
- **Cosmos DB**: Serverless with autoscale (~$25/month)
- **Service Bus**: Standard tier (~$10/month)
- **Blob Storage**: LRS, Hot tier (~$5/month for 100GB)
- **Application Insights**: (~$5/month)

**Estimated Monthly**: $45-60 for POC/dev

### Claude AI Costs
- **Claude 3.5 Sonnet**: ~$3/million input tokens, $15/million output tokens
- **Average document**: ~2000 input tokens, ~500 output tokens
- **Cost per document**: ~$0.01
- **1000 documents**: ~$10

**Total POC**: ~$55-70/month for moderate usage

### Cost-Saving Features
- Consumption Functions (pay per execution)
- Serverless Cosmos DB (pay per RU)
- Auto-archive old documents
- TTL for automatic cleanup
- Mock AI mode for testing
- Local development environment

## 📊 Monitoring & Debugging

### Application Insights

View metrics in Azure Portal:
- Function execution times
- Success/failure rates
- Document processing throughput
- Claude API usage

### Local Debugging

**View Function logs**:
```bash
# In Functions terminal
# Logs appear automatically when processing
```

**View Cosmos DB data**:
```bash
# Open Cosmos DB Emulator Explorer
open https://localhost:8081/_explorer/index.html
```

**View Blob Storage**:
```bash
# Install Azure Storage Explorer
# Connect to local emulator
```

### Common Issues

**1. Cosmos DB connection fails locally**
- Ensure Cosmos emulator is running: `docker ps`
- Trust the SSL certificate: `curl -k https://localhost:8081`

**2. Function can't find Anthropic API key**
- Check `.env` file has correct key
- Or set `ENABLE_MOCK_AI=true`

**3. Web UI can't connect to Functions**
- Ensure Functions are running on port 7071
- Check CORS settings in local.settings.json

**4. Document upload fails**
- Check file size (max 50MB)
- Verify file type (PDF, PNG, JPG, TIFF)
- Check Azurite is running

## 🔧 Advanced Configuration

### Custom Extraction Prompts

Edit `src/functions/services/claude_service.py`:

```python
def _get_extraction_prompt(self) -> str:
    return """Your custom extraction prompt here..."""
```

### Add New Document Types

Extend the prompt to handle new document types:

```python
For purchase orders, include:
- po_number
- vendor
- delivery_date
- line_items: [{sku, description, quantity, price}]
```

### Adjust Processing Limits

In `variables.tf`:

```hcl
max_document_size_mb    = 100  # Increase to 100MB
document_retention_days = 90   # Keep for 90 days
```

### Enable Production Features

Set `enable_cost_optimization = false` to enable:
- Premium Functions with VNet integration
- Private endpoints for all services
- Multi-region Cosmos DB
- GRS storage replication

## 📁 Project Structure

```
/infra
├── *.tf                        # Terraform infrastructure files
├── terraform.tfvars            # Your configuration
├── docker-compose.local.yml    # Local development environment
├── .env.example                # Environment template
│
├── /scripts
│   ├── setup-local.sh          # Local setup automation
│   ├── setup-cosmos.py         # Cosmos DB initialization
│   └── setup-storage.py        # Blob storage initialization
│
├── /src/functions              # Azure Functions
│   ├── function_app.py         # Main function definitions
│   ├── host.json               # Function runtime config
│   ├── requirements.txt        # Python dependencies
│   ├── local.settings.json     # Local configuration
│   │
│   ├── /services
│   │   ├── claude_service.py   # Claude AI integration
│   │   ├── cosmos_service.py   # Cosmos DB operations
│   │   └── storage_service.py  # Blob storage operations
│   │
│   └── /utils
│       └── config.py           # Configuration management
│
└── /src/web                    # React Web UI
    ├── package.json
    ├── Dockerfile
    ├── /src
    │   ├── App.js              # Main UI component
    │   └── App.css             # Styling
    └── /public
        └── index.html
```

## 🎬 Demo Flow

### For Stakeholders

1. **Show the architecture diagram** (above)
2. **Demonstrate local environment**:
   - Run `docker-compose up`
   - Show Azurite, Cosmos emulator running
3. **Upload sample document**:
   - Drag invoice PDF to web UI
   - Show real-time status updates
4. **View extracted data**:
   - Click "View Data" button
   - Show structured JSON output
   - Highlight confidence scores
5. **Show Azure deployment**:
   - Walk through Terraform files
   - Show cost optimization features
   - Demo auto-scaling capabilities

### Sample Documents

Create test documents in `/samples`:
- `invoice-sample.pdf`: Invoice with line items
- `receipt-sample.jpg`: Store receipt
- `form-sample.pdf`: Application form

## 🛠️ Troubleshooting

### Local Development

**Python version issues**:
```bash
pyenv install 3.11.0
pyenv local 3.11.0
```

**Docker out of memory**:
```bash
# Increase Docker memory to 4GB
# Docker Desktop → Settings → Resources → Memory
```

**Port conflicts**:
```bash
# Change ports in docker-compose.local.yml
# Or stop conflicting services
lsof -i :7071  # Find process using port
```

### Azure Deployment

**Terraform state issues**:
```bash
# Reset state if needed
terraform state rm azurerm_resource_group.main
terraform import azurerm_resource_group.main /subscriptions/...
```

**Function deployment fails**:
```bash
# Check function app exists
az functionapp list --query "[].name"

# Redeploy
func azure functionapp publish <name> --python
```

## 📚 Additional Resources

- [Azure Functions Python Guide](https://docs.microsoft.com/azure/azure-functions/functions-reference-python)
- [Anthropic Claude API Docs](https://docs.anthropic.com/)
- [Azure Event Grid](https://docs.microsoft.com/azure/event-grid/)
- [Cosmos DB Best Practices](https://docs.microsoft.com/azure/cosmos-db/best-practices)

## 🤝 Support

For issues or questions:
1. Check logs in Application Insights (Azure)
2. Review local logs in terminal
3. Check this documentation
4. Review Terraform output for deployment issues

## 📝 License

This project is for internal use and demonstration purposes.

---

**Last Updated**: 2025-10-07
**Version**: 1.0.0
**Status**: Ready for POC deployment
