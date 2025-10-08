"""
Claude AI Document Processing Service

This service demonstrates key distributed systems and event-driven architecture principles:

1. STATELESS DESIGN: Service maintains no state between requests, enabling horizontal scaling
   - Each request is independent and can be processed by any instance
   - Supports auto-scaling in serverless environments (Azure Functions)
   - Enables distributed processing across multiple workers

2. IDEMPOTENCY: Operations can be safely retried without side effects
   - Claude API calls are deterministic for the same input
   - Failures can be retried via Service Bus dead letter queues
   - Supports at-least-once message delivery guarantees

3. RESILIENCE PATTERNS:
   - Graceful degradation with mock mode for testing
   - Comprehensive error handling and logging
   - Configurable timeouts and retry logic (handled at Function level)

4. ASYNC PROCESSING: Designed for asynchronous, event-driven workflows
   - Processes documents triggered by events (blob upload -> Event Grid -> Service Bus)
   - Non-blocking operations suitable for high-volume processing
   - Integrates with distributed message queues

5. OBSERVABILITY: Structured logging and metrics for distributed tracing
   - Detailed logging at each step
   - Token usage tracking for cost monitoring
   - Confidence scoring for quality assurance
"""

import anthropic
import base64
import json
import logging
from typing import Dict, Any, Optional
from utils.config import Config

logger = logging.getLogger(__name__)


class ClaudeDocumentProcessor:
    """
    Service for processing documents using Claude AI.

    DISTRIBUTED SYSTEM DESIGN PRINCIPLES:

    1. STATELESS SERVICE PATTERN:
       - No instance-level state (only configuration)
       - Each request is self-contained with all required data
       - Can run on any compute node in the cluster
       - Supports horizontal scaling and load balancing

    2. EXTERNAL STATE MANAGEMENT:
       - All state stored externally (Cosmos DB, Blob Storage)
       - Service can restart without data loss
       - Multiple instances share same external state

    3. CONFIGURATION INJECTION:
       - Dependencies injected via Config object
       - Enables different configurations per environment
       - Facilitates testing with mock implementations
    """

    def __init__(self, config: Config):
        """
        Initialize the Claude document processor.

        INITIALIZATION PATTERN:
        - Lightweight initialization for fast cold starts (important in serverless)
        - API client created once per instance (connection pooling)
        - Mock mode support for local development without external dependencies

        Args:
            config: Configuration object with API keys and settings
        """
        self.config = config

        # FEATURE FLAG PATTERN: Enable/disable features without code changes
        if not config.enable_mock_ai:
            # Production: Initialize actual API client
            self.client = anthropic.Anthropic(api_key=config.anthropic_api_key)
        else:
            # Development/Testing: Use mock implementation
            # Allows testing event flow without API costs
            self.client = None

    async def extract_data(
        self,
        document_bytes: bytes,
        content_type: str,
        document_url: str
    ) -> Dict[str, Any]:
        """
        Extract structured data from a document using Claude AI.

        EVENT-DRIVEN ARCHITECTURE:
        This method is the core processing step in the event-driven workflow:

        Event Flow:
        1. Document uploaded to Blob Storage (Event Source)
        2. Event Grid detects BlobCreated event (Event Router)
        3. Service Bus receives event (Message Queue - ensures delivery)
        4. Azure Function triggered by queue message (Event Consumer)
        5. THIS METHOD called to process document (Business Logic)
        6. Results saved to Cosmos DB (State Store)
        7. Completion event published to queue (Event Producer)

        DISTRIBUTED PROCESSING CHARACTERISTICS:

        - ASYNC/AWAIT: Non-blocking I/O for efficient resource usage
          * Allows processing thousands of concurrent documents
          * Thread doesn't block waiting for Claude API response
          * Azure Functions can process multiple messages in parallel

        - RETRY-SAFE: Designed for automatic retry on failure
          * If this fails, Service Bus re-delivers message
          * Same document can be processed multiple times safely
          * Results are deterministic (same input = same output)

        - OBSERVABLE: Detailed logging for distributed tracing
          * Track document through entire pipeline
          * Application Insights correlates logs across services
          * Performance metrics for optimization

        - SCALABLE: Stateless design enables horizontal scaling
          * Multiple function instances process in parallel
          * Auto-scales based on queue depth
          * No coordination needed between instances

        Args:
            document_bytes: The document content as bytes
            content_type: MIME type of the document
            document_url: URL of the document in blob storage (for reference/audit)

        Returns:
            Dictionary containing extracted fields, confidence, and metadata

        Raises:
            Exception: On processing failure (triggers retry mechanism)
        """
        try:
            # FEATURE FLAG: Mock mode for testing without external API calls
            if self.config.enable_mock_ai:
                return self._mock_extraction(document_bytes, content_type)

            # STEP 1: Prepare document for Claude API
            # Base64 encoding required for API transmission
            base64_document = base64.standard_b64encode(document_bytes).decode("utf-8")

            # STEP 2: Determine correct media type for API
            media_type = self._get_claude_media_type(content_type)

            # STEP 3: Get extraction prompt (customizable per document type)
            prompt = self._get_extraction_prompt()

            # OBSERVABILITY: Log before external API call for tracing
            logger.info(f"Sending document to Claude (model: {self.config.claude_model})")

            # STEP 4: Call Claude API
            # EXTERNAL SERVICE INTEGRATION PATTERN:
            # - Timeout handled by client library
            # - Retries handled at higher level (Service Bus)
            # - Failures logged and propagated for retry
            message = self.client.messages.create(
                model=self.config.claude_model,
                max_tokens=self.config.max_tokens,
                messages=[
                    {
                        "role": "user",
                        "content": [
                            {
                                # Claude's vision capabilities process document as image
                                "type": "image",
                                "source": {
                                    "type": "base64",
                                    "media_type": media_type,
                                    "data": base64_document,
                                },
                            },
                            {
                                # Natural language prompt defines extraction schema
                                "type": "text",
                                "text": prompt
                            }
                        ],
                    }
                ],
            )

            # STEP 5: Extract and validate response
            response_text = message.content[0].text
            logger.info(f"Claude response received: {len(response_text)} characters")

            # STEP 6: Parse structured data from response
            # RESILIENCE PATTERN: Handle multiple response formats gracefully
            try:
                # Primary path: Direct JSON response
                extracted_data = json.loads(response_text)
            except json.JSONDecodeError:
                # Fallback: Extract JSON from markdown code block
                # Claude sometimes wraps JSON in markdown formatting
                if "```json" in response_text:
                    json_start = response_text.find("```json") + 7
                    json_end = response_text.find("```", json_start)
                    response_text = response_text[json_start:json_end].strip()
                    extracted_data = json.loads(response_text)
                else:
                    # Last resort: Return raw text for manual review
                    logger.warning("Could not parse JSON from Claude response")
                    extracted_data = {"raw_text": response_text}

            # STEP 7: Calculate confidence score for quality assessment
            # Enables downstream systems to filter low-confidence results
            confidence = self._calculate_confidence(extracted_data)

            # STEP 8: Return standardized response structure
            # SCHEMA PATTERN: Consistent response format for all documents
            return {
                "extractedFields": extracted_data,  # The actual extracted data
                "confidence": confidence,            # Quality score (0.0 - 1.0)
                "model": self.config.claude_model,   # AI model used (for auditing)
                "rawResponse": response_text,        # Full response (for debugging)
                "warnings": extracted_data.get("warnings", []),  # Data quality issues
                "usage": {
                    # COST TRACKING: Monitor API usage for billing/optimization
                    "input_tokens": message.usage.input_tokens,
                    "output_tokens": message.usage.output_tokens
                }
            }

        except Exception as e:
            # ERROR HANDLING PATTERN: Log and re-raise for upstream handling
            # Service Bus will retry based on delivery count
            # Dead Letter Queue catches permanently failed messages
            logger.error(f"Error extracting data with Claude: {str(e)}", exc_info=True)
            raise  # Re-raise to trigger retry mechanism

    def _get_claude_media_type(self, content_type: str) -> str:
        """
        Convert MIME type to Claude-compatible media type.

        ADAPTER PATTERN: Translate between external format (MIME) and API format

        Args:
            content_type: Standard MIME type from blob storage

        Returns:
            Claude API compatible media type
        """
        mime_to_claude = {
            "application/pdf": "application/pdf",
            "image/png": "image/png",
            "image/jpeg": "image/jpeg",
            "image/jpg": "image/jpeg",
            "image/gif": "image/gif",
            "image/webp": "image/webp"
        }
        return mime_to_claude.get(content_type.lower(), "application/pdf")

    def _get_extraction_prompt(self) -> str:
        """
        Get the prompt template for document extraction.

        TEMPLATE PATTERN: Centralized prompt management

        CUSTOMIZATION POINT: Modify this prompt to:
        - Add new document types
        - Change extraction schema
        - Adjust validation rules
        - Support different languages

        PROMPT ENGINEERING PRINCIPLES:
        1. Clear structure definition (JSON schema)
        2. Multiple document type support
        3. Validation instructions (calculations, dates)
        4. Error handling instructions (null for missing data)
        5. Quality checks (warnings array)

        Returns:
            Prompt text for Claude API
        """
        return """Extract structured data from this document.

Analyze the document and extract all relevant information into a JSON structure.

For invoices/receipts, include:
- vendor: {name, address, phone, email, tax_id}
- invoice_number
- date (ISO 8601 format: YYYY-MM-DD)
- due_date (if applicable)
- line_items: [{description, quantity, unit_price, total}]
- subtotal
- tax
- total
- payment_terms
- currency

For forms/applications, include:
- form_type
- applicant: {name, address, phone, email}
- fields: {field_name: field_value}
- signatures: [{name, date, title}]
- submission_date

For general documents, include:
- document_type
- title
- date
- author
- summary
- key_entities: [{type, name, value}]
- tables: [extracted table data]

Additional requirements:
1. Return ONLY valid JSON, no markdown formatting
2. If a field is unclear or missing, set it to null
3. Include a "warnings" array with any issues (e.g., ["Date format unclear", "Total doesn't match sum"])
4. Include a "document_type" field to categorize the document
5. Validate calculations (e.g., line items should sum to subtotal)
6. Extract dates in ISO 8601 format
7. For currency values, include the currency code

Return the data as a JSON object."""

    def _calculate_confidence(self, extracted_data: Dict[str, Any]) -> float:
        """
        Calculate confidence score for extracted data quality.

        QUALITY METRICS PATTERN: Quantify data quality for downstream decisions

        Uses heuristics:
        - Warnings from Claude reduce confidence
        - Null/missing fields reduce confidence
        - Complete, validated data has high confidence

        BUSINESS VALUE:
        - High confidence (>0.8): Automatically process
        - Medium confidence (0.5-0.8): Flag for review
        - Low confidence (<0.5): Requires manual processing

        This enables SLA-based routing in distributed systems.

        Args:
            extracted_data: Data extracted from document

        Returns:
            Confidence score between 0.0 and 1.0
        """
        confidence = 1.0

        # Reduce confidence for each warning reported by Claude
        # Warnings indicate potential data quality issues
        warnings = extracted_data.get("warnings", [])
        confidence -= len(warnings) * 0.1

        # Reduce confidence for missing/null data
        # More nulls = less complete extraction
        null_count = sum(1 for v in str(extracted_data).split() if v == "null")
        confidence -= null_count * 0.05

        # Ensure confidence stays within valid range [0.0, 1.0]
        return max(0.0, min(1.0, confidence))

    def _mock_extraction(self, document_bytes: bytes, content_type: str) -> Dict[str, Any]:
        """
        Mock extraction for local development and testing.

        TESTING PATTERN: Enable development without external dependencies

        BENEFITS FOR DISTRIBUTED SYSTEMS:
        - Test event flow without API costs
        - Deterministic results for integration testing
        - Fast feedback loop during development
        - No rate limits or quotas
        - Works offline

        LOCAL DEVELOPMENT WORKFLOW:
        1. Set ENABLE_MOCK_AI=true in local.settings.json
        2. Upload documents to Azurite (local storage emulator)
        3. Process through full event pipeline locally
        4. Verify data in Cosmos DB emulator
        5. Test UI without production costs

        Args:
            document_bytes: Document content (not used in mock)
            content_type: Content type (not used in mock)

        Returns:
            Mock extraction result matching production schema
        """
        logger.info("Using mock AI extraction (ENABLE_MOCK_AI=true)")

        # Return realistic sample data for testing
        # Schema matches real Claude responses exactly
        return {
            "extractedFields": {
                "document_type": "invoice",
                "vendor": {
                    "name": "Mock Company Inc.",
                    "address": "123 Main St, Anytown, USA",
                    "phone": "+1-555-0123",
                    "email": "billing@mockcompany.com",
                    "tax_id": "12-3456789"
                },
                "invoice_number": "INV-2024-001",
                "date": "2024-01-15",
                "due_date": "2024-02-15",
                "line_items": [
                    {
                        "description": "Professional Services",
                        "quantity": 10.0,
                        "unit_price": 150.00,
                        "total": 1500.00
                    },
                    {
                        "description": "Software License",
                        "quantity": 1.0,
                        "unit_price": 500.00,
                        "total": 500.00
                    }
                ],
                "subtotal": 2000.00,
                "tax": 200.00,
                "total": 2200.00,
                "currency": "USD",
                "payment_terms": "Net 30",
                "warnings": []
            },
            "confidence": 1.0,
            "model": "mock-ai",
            "rawResponse": "Mock response",
            "warnings": [],
            "usage": {
                "input_tokens": 0,
                "output_tokens": 0
            }
        }
