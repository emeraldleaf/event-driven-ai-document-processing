import logging
from azure.cosmos.aio import CosmosClient
from azure.cosmos import exceptions, PartitionKey
from azure.identity.aio import DefaultAzureCredential
from typing import Dict, Any, List, Optional
from utils.config import Config

logger = logging.getLogger(__name__)


class CosmosService:
    """Service for interacting with Azure Cosmos DB."""

    def __init__(self, config: Config):
        self.config = config
        self.credential = DefaultAzureCredential()
        self.client = None
        self.database = None
        self.documents_container = None
        self.extracted_container = None
        self.jobs_container = None

    async def _ensure_initialized(self):
        """Ensure Cosmos client is initialized."""
        if self.client is None:
            self.client = CosmosClient(
                self.config.cosmos_endpoint,
                credential=self.credential
            )
            self.database = self.client.get_database_client(self.config.cosmos_database)
            self.documents_container = self.database.get_container_client(
                self.config.cosmos_documents_container
            )
            self.extracted_container = self.database.get_container_client(
                self.config.cosmos_extracted_container
            )
            self.jobs_container = self.database.get_container_client(
                self.config.cosmos_jobs_container
            )

    async def create_document(self, document: Dict[str, Any]) -> Dict[str, Any]:
        """Create a document record in Cosmos DB."""
        try:
            await self._ensure_initialized()
            result = await self.documents_container.create_item(body=document)
            logger.info(f"Created document record: {document['id']}")
            return result
        except Exception as e:
            logger.error(f"Error creating document in Cosmos DB: {str(e)}")
            raise

    async def create_extracted_data(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """Create an extracted data record in Cosmos DB."""
        try:
            await self._ensure_initialized()
            result = await self.extracted_container.create_item(body=data)
            logger.info(f"Created extracted data record: {data['id']}")
            return result
        except Exception as e:
            logger.error(f"Error creating extracted data in Cosmos DB: {str(e)}")
            raise

    async def create_job(self, job: Dict[str, Any]) -> Dict[str, Any]:
        """Create a processing job record in Cosmos DB."""
        try:
            await self._ensure_initialized()
            result = await self.jobs_container.create_item(body=job)
            logger.info(f"Created job record: {job['id']}")
            return result
        except Exception as e:
            logger.error(f"Error creating job in Cosmos DB: {str(e)}")
            raise

    async def update_job(self, job: Dict[str, Any]) -> Dict[str, Any]:
        """Update a processing job record in Cosmos DB."""
        try:
            await self._ensure_initialized()
            result = await self.jobs_container.upsert_item(body=job)
            logger.info(f"Updated job record: {job['id']}")
            return result
        except Exception as e:
            logger.error(f"Error updating job in Cosmos DB: {str(e)}")
            raise

    async def get_documents(
        self,
        limit: int = 50,
        status: Optional[str] = None
    ) -> List[Dict[str, Any]]:
        """Get documents with optional filtering."""
        try:
            await self._ensure_initialized()

            # Build query
            if status:
                query = f"SELECT * FROM c WHERE c.status = @status ORDER BY c.uploadDate DESC OFFSET 0 LIMIT {limit}"
                parameters = [{"name": "@status", "value": status}]
            else:
                query = f"SELECT * FROM c ORDER BY c.uploadDate DESC OFFSET 0 LIMIT {limit}"
                parameters = []

            items = []
            async for item in self.documents_container.query_items(
                query=query,
                parameters=parameters,
                enable_cross_partition_query=True
            ):
                items.append(item)

            logger.info(f"Retrieved {len(items)} documents")
            return items

        except Exception as e:
            logger.error(f"Error querying documents: {str(e)}")
            raise

    async def get_extracted_data(self, document_id: str) -> Optional[Dict[str, Any]]:
        """Get extracted data for a specific document."""
        try:
            await self._ensure_initialized()

            query = "SELECT * FROM c WHERE c.documentId = @documentId"
            parameters = [{"name": "@documentId", "value": document_id}]

            items = []
            async for item in self.extracted_container.query_items(
                query=query,
                parameters=parameters,
                enable_cross_partition_query=True
            ):
                items.append(item)

            if items:
                logger.info(f"Retrieved extracted data for document: {document_id}")
                return items[0]
            else:
                logger.warning(f"No extracted data found for document: {document_id}")
                return None

        except Exception as e:
            logger.error(f"Error getting extracted data: {str(e)}")
            raise
