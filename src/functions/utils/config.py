import os
from typing import Optional


class Config:
    """Configuration class for loading environment variables."""

    def __init__(self):
        # Anthropic API
        self.anthropic_api_key: str = os.getenv("ANTHROPIC_API_KEY", "")
        self.claude_model: str = os.getenv("CLAUDE_MODEL", "claude-3-5-sonnet-20241022")
        self.max_tokens: int = int(os.getenv("MAX_TOKENS", "4096"))

        # Azure Storage
        self.document_storage_connection: str = os.getenv("DOCUMENT_STORAGE_CONNECTION", "")
        self.incoming_container: str = os.getenv("INCOMING_CONTAINER", "documents-incoming")
        self.processed_container: str = os.getenv("PROCESSED_CONTAINER", "documents-processed")
        self.failed_container: str = os.getenv("FAILED_CONTAINER", "documents-failed")

        # Cosmos DB
        self.cosmos_endpoint: str = os.getenv("COSMOS_ENDPOINT", "")
        self.cosmos_database: str = os.getenv("COSMOS_DATABASE", "Application")
        self.cosmos_documents_container: str = os.getenv("COSMOS_DOCUMENTS_CONTAINER", "Documents")
        self.cosmos_extracted_container: str = os.getenv("COSMOS_EXTRACTED_CONTAINER", "ExtractedData")
        self.cosmos_jobs_container: str = os.getenv("COSMOS_JOBS_CONTAINER", "ProcessingJobs")

        # Service Bus
        self.servicebus_connection: str = os.getenv("SERVICEBUS_CONNECTION", "")
        self.processing_queue: str = os.getenv("PROCESSING_QUEUE", "document-processing")
        self.completion_queue: str = os.getenv("COMPLETION_QUEUE", "document-extraction-complete")

        # Configuration
        self.max_document_size_mb: int = int(os.getenv("MAX_DOCUMENT_SIZE_MB", "50"))
        self.enable_detailed_logging: bool = os.getenv("ENABLE_DETAILED_LOGGING", "false").lower() == "true"

        # Feature Flags
        self.enable_mock_ai: bool = os.getenv("ENABLE_MOCK_AI", "false").lower() == "true"

    def validate(self) -> bool:
        """Validate that required configuration is present."""
        if not self.enable_mock_ai and not self.anthropic_api_key:
            raise ValueError("ANTHROPIC_API_KEY is required when ENABLE_MOCK_AI is false")

        if not self.cosmos_endpoint:
            raise ValueError("COSMOS_ENDPOINT is required")

        return True
