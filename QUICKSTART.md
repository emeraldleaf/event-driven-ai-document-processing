# Quick Start Guide - Document Processor

Get up and running in 5 minutes!

## Option 1: Local Development (No Azure Required)

### Prerequisites
- Docker Desktop installed and running
- Python 3.11
- Node.js 18+
- Azure Functions Core Tools (`npm install -g azure-functions-core-tools@4`)

### Steps

1. **Setup environment**:
```bash
# Copy environment template
cp .env.example .env

# Edit and set ENABLE_MOCK_AI=true (no API key needed for testing)
echo "ENABLE_MOCK_AI=true" >> .env
```

2. **Start local services**:
```bash
# Run setup script
chmod +x scripts/setup-local.sh
./scripts/setup-local.sh

# This will:
# - Start Docker containers (Azurite + Cosmos DB)
# - Create required containers and databases
# - Install Python dependencies
```

3. **Start Azure Functions** (Terminal 1):
```bash
cd src/functions
source .venv/bin/activate
func start
```

4. **Start Web UI** (Terminal 2):
```bash
cd src/web
npm install
npm start
```

5. **Open browser**:
- Go to http://localhost:3000
- Upload a document (PDF or image)
- View extracted data!

### What You'll See

With `ENABLE_MOCK_AI=true`, you'll get sample extracted invoice data without needing an Anthropic API key. Perfect for testing the architecture!

## Option 2: Local with Real AI

### Prerequisites
- Same as Option 1
- Anthropic API key (get from https://console.anthropic.com)

### Steps

1. **Add API key to .env**:
```bash
cp .env.example .env
echo "ANTHROPIC_API_KEY=sk-ant-your-key-here" >> .env
echo "ENABLE_MOCK_AI=false" >> .env
```

2. **Follow steps 2-5 from Option 1**

Now your documents will be processed by Claude AI!

## Option 3: Deploy to Azure

### Prerequisites
- Azure subscription
- Azure CLI installed and logged in
- Terraform installed
- Anthropic API key

### Steps

1. **Create terraform.tfvars**:
```hcl
location                 = "eastus2"
environment              = "dev"
app_name                 = "docprocessor"
anthropic_api_key        = "sk-ant-your-key-here"
enable_cost_optimization = true

# Optional - if you have existing resources
existing_front_door_id   = ""
on_prem_sql_server = {
  server_name   = ""
  database_name = ""
}
management_vm_admin_password = "SecurePassword123!"
```

2. **Deploy infrastructure**:
```bash
terraform init
terraform plan
terraform apply
```

3. **Deploy function code**:
```bash
cd src/functions
func azure functionapp publish $(terraform output -raw document_function_app_name)
```

4. **Deploy web UI**:
```bash
cd src/web
npm run build

# Upload to Azure Storage static website
az storage blob upload-batch \
  --account-name $(terraform output -raw document_storage_account_name) \
  --destination '$web' \
  --source build/
```

5. **Get URLs**:
```bash
echo "Web UI: $(terraform output -raw document_storage_static_website_url)"
echo "API: $(terraform output -raw document_function_app_url)"
```

## Testing

### Sample cURL Commands

**Upload a document**:
```bash
curl -X POST http://localhost:7071/api/upload \
  -F "file=@/path/to/invoice.pdf"
```

**Get all documents**:
```bash
curl http://localhost:7071/api/documents
```

**Get extracted data**:
```bash
curl http://localhost:7071/api/documents/{document-id}/data
```

### Sample Documents

Create test files in a `samples/` folder:

**invoice.pdf** - Sample invoice with:
- Vendor information
- Line items
- Totals

**receipt.jpg** - Store receipt photo

**form.pdf** - Application form

## What Gets Extracted?

Claude will extract structured data like:

```json
{
  "document_type": "invoice",
  "vendor": {
    "name": "Acme Corp",
    "address": "123 Main St",
    "tax_id": "12-3456789"
  },
  "invoice_number": "INV-2024-001",
  "date": "2024-01-15",
  "line_items": [
    {
      "description": "Professional Services",
      "quantity": 10,
      "unit_price": 150.00,
      "total": 1500.00
    }
  ],
  "subtotal": 1500.00,
  "tax": 150.00,
  "total": 1650.00
}
```

## Troubleshooting

**Docker not running**:
```bash
# Start Docker Desktop and try again
```

**Port 7071 already in use**:
```bash
# Find and kill the process
lsof -i :7071
kill -9 <PID>
```

**Cosmos DB emulator won't start**:
```bash
# Increase Docker memory to 4GB
# Docker Desktop → Settings → Resources → Memory
```

**Can't access localhost:3000**:
```bash
# Make sure web server started successfully
# Check for errors in terminal
cd src/web
npm start
```

## Next Steps

- Read [DOCUMENT_PROCESSING_GUIDE.md](./DOCUMENT_PROCESSING_GUIDE.md) for full documentation
- Customize extraction prompts in `src/functions/services/claude_service.py`
- Add custom document types
- Deploy to Azure for production use

## Cost Estimate

**Local Development**: Free! (except Claude API if used)

**Azure POC** (with cost optimization):
- Azure: ~$50/month
- Claude API: ~$10 per 1000 documents
- Total: ~$60/month for POC

**Production** (without cost optimization):
- Azure: ~$200-500/month
- Claude API: Based on volume

## Support

- Check logs in terminal
- Review `DOCUMENT_PROCESSING_GUIDE.md`
- Check Application Insights (Azure)
