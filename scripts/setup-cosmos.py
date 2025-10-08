#!/usr/bin/env python3
"""
Setup script for creating Cosmos DB database and containers (local development).
"""

from azure.cosmos import CosmosClient, PartitionKey
import sys
import urllib3

# Disable SSL warnings for local emulator
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

# Cosmos DB Emulator connection details
COSMOS_ENDPOINT = "https://localhost:8081"
COSMOS_KEY = "C2y6yDjf5/R+ob0N8A7Cgv30VRDJIWEHLM+4QDU5DE2nQ9nDuVTqobD4b8mGGyPMbIZnqyMsEcaGQy67XIw/Jw=="

DATABASE_NAME = "Application"

CONTAINERS = [
    {
        "name": "Documents",
        "partition_key": "/uploadDate",
        "default_ttl": 2592000  # 30 days
    },
    {
        "name": "ExtractedData",
        "partition_key": "/documentId",
        "default_ttl": 2592000  # 30 days
    },
    {
        "name": "ProcessingJobs",
        "partition_key": "/status",
        "default_ttl": 7776000  # 90 days
    },
    {
        "name": "SessionState",
        "partition_key": "/sessionId",
        "default_ttl": 86400  # 24 hours
    }
]


def main():
    print("Setting up Cosmos DB database and containers...")

    try:
        # Create Cosmos client (disable SSL verification for local emulator)
        client = CosmosClient(
            COSMOS_ENDPOINT,
            COSMOS_KEY,
            connection_verify=False
        )

        # Create database
        try:
            database = client.create_database(DATABASE_NAME)
            print(f"✅ Created database: {DATABASE_NAME}")
        except Exception:
            database = client.get_database_client(DATABASE_NAME)
            print(f"ℹ️  Database already exists: {DATABASE_NAME}")

        # Create containers
        for container_config in CONTAINERS:
            try:
                container = database.create_container(
                    id=container_config["name"],
                    partition_key=PartitionKey(path=container_config["partition_key"]),
                    default_ttl=container_config["default_ttl"]
                )
                print(f"✅ Created container: {container_config['name']}")
            except Exception:
                print(f"ℹ️  Container already exists: {container_config['name']}")

        print("\n✅ Cosmos DB setup complete!")
        return 0

    except Exception as e:
        print(f"❌ Error setting up Cosmos DB: {str(e)}")
        print("\nMake sure Cosmos DB emulator is running:")
        print("  docker-compose -f docker-compose.local.yml up -d cosmos-db")
        return 1


if __name__ == "__main__":
    sys.exit(main())
