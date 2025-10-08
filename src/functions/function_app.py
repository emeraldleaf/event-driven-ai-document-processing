import azure.functions as func
import logging
import os
import json
from datetime import datetime
import uuid

# Import our custom modules
from services.claude_service import ClaudeDocumentProcessor
from services.storage_service import StorageService
from services.cosmos_service import CosmosService
from utils.config import Config

# Initialize Function App
app = func.FunctionApp()

# Initialize services
config = Config()
claude_processor = ClaudeDocumentProcessor(config)
storage_service = StorageService(config)
cosmos_service = CosmosService(config)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


@app.function_name(name="ProcessDocument")
@app.service_bus_queue_trigger(
    arg_name="msg",
    queue_name="%PROCESSING_QUEUE%",
    connection="SERVICEBUS_CONNECTION"
)
async def process_document(msg: func.ServiceBusMessage):
    """
    Main document processing function triggered by Service Bus queue.
    Processes documents uploaded to blob storage using Claude AI.
    """
    try:
        logger.info(f"Processing message: {msg.message_id}")

        # Parse the Event Grid message
        event_data = json.loads(msg.get_body().decode('utf-8'))
        logger.info(f"Event data: {json.dumps(event_data, indent=2)}")

        # Extract blob information
        blob_url = event_data.get('data', {}).get('url')
        if not blob_url:
            # Handle direct blob URL
            blob_url = event_data.get('subject', '')

        logger.info(f"Processing document from: {blob_url}")

        # Create processing job
        job_id = str(uuid.uuid4())
        job = {
            "id": job_id,
            "documentUrl": blob_url,
            "status": "processing",
            "createdAt": datetime.utcnow().isoformat(),
            "updatedAt": datetime.utcnow().isoformat()
        }
        await cosmos_service.create_job(job)

        # Download document from blob storage
        logger.info(f"Downloading document: {blob_url}")
        document_bytes, content_type = await storage_service.download_document(blob_url)

        # Check document size
        size_mb = len(document_bytes) / (1024 * 1024)
        if size_mb > float(config.max_document_size_mb):
            raise ValueError(f"Document too large: {size_mb:.2f}MB (max: {config.max_document_size_mb}MB)")

        logger.info(f"Document downloaded: {size_mb:.2f}MB, type: {content_type}")

        # Process document with Claude
        logger.info("Sending document to Claude for processing...")
        extraction_result = await claude_processor.extract_data(
            document_bytes=document_bytes,
            content_type=content_type,
            document_url=blob_url
        )

        logger.info(f"Extraction complete: {len(extraction_result.get('extractedFields', {}))} fields extracted")

        # Save document metadata to Cosmos DB
        document_record = {
            "id": str(uuid.uuid4()),
            "blobUrl": blob_url,
            "uploadDate": datetime.utcnow().isoformat(),
            "status": "completed",
            "contentType": content_type,
            "sizeBytes": len(document_bytes),
            "jobId": job_id,
            "userId": event_data.get('userId', 'anonymous'),
            "fileName": blob_url.split('/')[-1]
        }
        await cosmos_service.create_document(document_record)

        # Save extracted data to Cosmos DB
        extracted_record = {
            "id": str(uuid.uuid4()),
            "documentId": document_record["id"],
            "extractedFields": extraction_result.get("extractedFields", {}),
            "confidence": extraction_result.get("confidence", 0.0),
            "model": extraction_result.get("model", ""),
            "extractedAt": datetime.utcnow().isoformat(),
            "warnings": extraction_result.get("warnings", []),
            "rawResponse": extraction_result.get("rawResponse", "")
        }
        await cosmos_service.create_extracted_data(extracted_record)

        # Move document to processed container
        await storage_service.move_to_processed(blob_url, document_record["id"])

        # Update job status
        job["status"] = "completed"
        job["updatedAt"] = datetime.utcnow().isoformat()
        job["documentId"] = document_record["id"]
        await cosmos_service.update_job(job)

        # Send completion notification
        completion_message = {
            "documentId": document_record["id"],
            "jobId": job_id,
            "status": "completed",
            "fieldsExtracted": len(extraction_result.get('extractedFields', {})),
            "completedAt": datetime.utcnow().isoformat()
        }
        await storage_service.send_completion_notification(completion_message)

        logger.info(f"Document processing completed successfully: {document_record['id']}")

    except Exception as e:
        logger.error(f"Error processing document: {str(e)}", exc_info=True)

        # Update job status to failed
        try:
            job["status"] = "failed"
            job["error"] = str(e)
            job["updatedAt"] = datetime.utcnow().isoformat()
            await cosmos_service.update_job(job)

            # Move to failed container
            if 'blob_url' in locals():
                await storage_service.move_to_failed(blob_url, str(e))
        except Exception as inner_e:
            logger.error(f"Error updating failure status: {str(inner_e)}")

        # Re-raise to trigger Service Bus retry
        raise


@app.function_name(name="UploadDocument")
@app.route(route="upload", methods=["POST"], auth_level=func.AuthLevel.ANONYMOUS)
async def upload_document(req: func.HttpRequest) -> func.HttpResponse:
    """
    HTTP endpoint for uploading documents directly.
    Uploads to blob storage which triggers the Event Grid -> Service Bus flow.
    """
    try:
        # Get file from request
        files = req.files.getlist('file')
        if not files:
            return func.HttpResponse(
                json.dumps({"error": "No file provided"}),
                status_code=400,
                mimetype="application/json"
            )

        file = files[0]
        file_content = file.read()

        # Validate file size
        size_mb = len(file_content) / (1024 * 1024)
        if size_mb > float(config.max_document_size_mb):
            return func.HttpResponse(
                json.dumps({"error": f"File too large: {size_mb:.2f}MB (max: {config.max_document_size_mb}MB)"}),
                status_code=400,
                mimetype="application/json"
            )

        # Upload to blob storage
        blob_url = await storage_service.upload_document(
            file_name=file.filename,
            file_content=file_content,
            content_type=file.content_type
        )

        logger.info(f"Document uploaded: {blob_url}")

        return func.HttpResponse(
            json.dumps({
                "message": "Document uploaded successfully",
                "blobUrl": blob_url,
                "fileName": file.filename,
                "sizeBytes": len(file_content)
            }),
            status_code=200,
            mimetype="application/json"
        )

    except Exception as e:
        logger.error(f"Error uploading document: {str(e)}", exc_info=True)
        return func.HttpResponse(
            json.dumps({"error": str(e)}),
            status_code=500,
            mimetype="application/json"
        )


@app.function_name(name="GetDocuments")
@app.route(route="documents", methods=["GET"], auth_level=func.AuthLevel.ANONYMOUS)
async def get_documents(req: func.HttpRequest) -> func.HttpResponse:
    """
    HTTP endpoint to retrieve document processing history.
    """
    try:
        # Get query parameters
        limit = int(req.params.get('limit', '50'))
        status = req.params.get('status')

        # Query Cosmos DB
        documents = await cosmos_service.get_documents(limit=limit, status=status)

        return func.HttpResponse(
            json.dumps({
                "documents": documents,
                "count": len(documents)
            }),
            status_code=200,
            mimetype="application/json"
        )

    except Exception as e:
        logger.error(f"Error retrieving documents: {str(e)}", exc_info=True)
        return func.HttpResponse(
            json.dumps({"error": str(e)}),
            status_code=500,
            mimetype="application/json"
        )


@app.function_name(name="GetExtractedData")
@app.route(route="documents/{document_id}/data", methods=["GET"], auth_level=func.AuthLevel.ANONYMOUS)
async def get_extracted_data(req: func.HttpRequest) -> func.HttpResponse:
    """
    HTTP endpoint to retrieve extracted data for a specific document.
    """
    try:
        document_id = req.route_params.get('document_id')

        # Query Cosmos DB
        extracted_data = await cosmos_service.get_extracted_data(document_id)

        if not extracted_data:
            return func.HttpResponse(
                json.dumps({"error": "Document not found"}),
                status_code=404,
                mimetype="application/json"
            )

        return func.HttpResponse(
            json.dumps(extracted_data),
            status_code=200,
            mimetype="application/json"
        )

    except Exception as e:
        logger.error(f"Error retrieving extracted data: {str(e)}", exc_info=True)
        return func.HttpResponse(
            json.dumps({"error": str(e)}),
            status_code=500,
            mimetype="application/json"
        )


@app.function_name(name="HealthCheck")
@app.route(route="health", methods=["GET"], auth_level=func.AuthLevel.ANONYMOUS)
async def health_check(req: func.HttpRequest) -> func.HttpResponse:
    """
    Health check endpoint for monitoring.
    """
    return func.HttpResponse(
        json.dumps({
            "status": "healthy",
            "timestamp": datetime.utcnow().isoformat(),
            "version": "1.0.0"
        }),
        status_code=200,
        mimetype="application/json"
    )
