#!/bin/bash

# Setup script for local development environment
set -e

echo "🚀 Setting up local development environment for Document Processor..."

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo "❌ Docker is not running. Please start Docker and try again."
    exit 1
fi

# Check if Python 3.11 is installed
if ! command -v python3.11 &> /dev/null; then
    echo "⚠️  Python 3.11 not found. Installing recommended..."
    echo "Please install Python 3.11 manually or use pyenv."
fi

# Check if Azure Functions Core Tools is installed
if ! command -v func &> /dev/null; then
    echo "⚠️  Azure Functions Core Tools not found."
    echo "Installing via npm..."
    npm install -g azure-functions-core-tools@4 --unsafe-perm true
fi

# Create .env file if it doesn't exist
if [ ! -f .env ]; then
    echo "📝 Creating .env file from template..."
    cp .env.example .env
    echo "⚠️  Please edit .env and add your ANTHROPIC_API_KEY"
fi

# Start Docker Compose services
echo "🐳 Starting Docker services (Azurite + Cosmos DB)..."
docker-compose -f docker-compose.local.yml up -d azurite cosmos-db

# Wait for services to be ready
echo "⏳ Waiting for services to be ready..."
sleep 5

# Create Cosmos DB database and containers
echo "📦 Setting up Cosmos DB database and containers..."
python3 scripts/setup-cosmos.py

# Create blob storage containers
echo "📦 Setting up blob storage containers..."
python3 scripts/setup-storage.py

# Install Python dependencies for Functions
echo "📦 Installing Python dependencies..."
cd src/functions
python3.11 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cd ../..

echo "✅ Local development environment setup complete!"
echo ""
echo "📋 Next steps:"
echo "1. Edit .env and add your Anthropic API key (or use ENABLE_MOCK_AI=true)"
echo "2. Start the Functions runtime: cd src/functions && func start"
echo "3. Start the web UI: docker-compose -f docker-compose.local.yml up web-ui"
echo "4. Open http://localhost:3000 to upload documents"
echo ""
echo "📚 Useful commands:"
echo "  - View logs: docker-compose -f docker-compose.local.yml logs -f"
echo "  - Stop services: docker-compose -f docker-compose.local.yml down"
echo "  - Reset data: docker-compose -f docker-compose.local.yml down -v"
