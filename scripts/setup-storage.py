#!/usr/bin/env python3
"""
Setup script for creating blob storage containers in Azurite (local development).
"""

from azure.storage.blob import BlobServiceClient
import sys

# Azurite connection string
CONNECTION_STRING = (
    "DefaultEndpointsProtocol=http;"
    "AccountName=devstoreaccount1;"
    "AccountKey=Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw==;"
    "BlobEndpoint=http://127.0.0.1:10000/devstoreaccount1;"
)

CONTAINERS = [
    "documents-incoming",
    "documents-processed",
    "documents-failed",
    "$web"
]


def main():
    print("Setting up blob storage containers...")

    try:
        # Create blob service client
        blob_service_client = BlobServiceClient.from_connection_string(CONNECTION_STRING)

        # Create containers
        for container_name in CONTAINERS:
            try:
                container_client = blob_service_client.get_container_client(container_name)
                if not container_client.exists():
                    container_client.create_container()
                    print(f"✅ Created container: {container_name}")
                else:
                    print(f"ℹ️  Container already exists: {container_name}")
            except Exception as e:
                print(f"❌ Error creating container {container_name}: {str(e)}")

        print("\n✅ Blob storage setup complete!")
        return 0

    except Exception as e:
        print(f"❌ Error setting up blob storage: {str(e)}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
