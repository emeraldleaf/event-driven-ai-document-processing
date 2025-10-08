import React, { useState, useEffect, useCallback } from 'react';
import { useDropzone } from 'react-dropzone';
import axios from 'axios';
import './App.css';

const API_URL = process.env.REACT_APP_API_URL || 'http://localhost:7071/api';

function App() {
  const [documents, setDocuments] = useState([]);
  const [uploading, setUploading] = useState(false);
  const [selectedDocument, setSelectedDocument] = useState(null);
  const [extractedData, setExtractedData] = useState(null);

  // Fetch documents on load
  useEffect(() => {
    fetchDocuments();
    const interval = setInterval(fetchDocuments, 5000); // Refresh every 5 seconds
    return () => clearInterval(interval);
  }, []);

  const fetchDocuments = async () => {
    try {
      const response = await axios.get(`${API_URL}/documents?limit=50`);
      setDocuments(response.data.documents || []);
    } catch (error) {
      console.error('Error fetching documents:', error);
    }
  };

  const onDrop = useCallback(async (acceptedFiles) => {
    for (const file of acceptedFiles) {
      await uploadFile(file);
    }
  }, []);

  const uploadFile = async (file) => {
    setUploading(true);
    try {
      const formData = new FormData();
      formData.append('file', file);

      await axios.post(`${API_URL}/upload`, formData, {
        headers: {
          'Content-Type': 'multipart/form-data',
        },
      });

      // Refresh documents list
      setTimeout(fetchDocuments, 1000);
    } catch (error) {
      console.error('Error uploading file:', error);
      alert(`Error uploading ${file.name}: ${error.message}`);
    } finally {
      setUploading(false);
    }
  };

  const viewExtractedData = async (documentId) => {
    try {
      const response = await axios.get(`${API_URL}/documents/${documentId}/data`);
      setExtractedData(response.data);
      setSelectedDocument(documentId);
    } catch (error) {
      console.error('Error fetching extracted data:', error);
      alert('Error fetching extracted data');
    }
  };

  const { getRootProps, getInputProps, isDragActive } = useDropzone({
    onDrop,
    accept: {
      'application/pdf': ['.pdf'],
      'image/png': ['.png'],
      'image/jpeg': ['.jpg', '.jpeg'],
      'image/tiff': ['.tiff', '.tif']
    },
    maxSize: 50 * 1024 * 1024, // 50MB
  });

  const formatDate = (dateString) => {
    return new Date(dateString).toLocaleString();
  };

  const getStatusBadge = (status) => {
    const badges = {
      completed: '✅ Completed',
      processing: '⏳ Processing',
      failed: '❌ Failed',
      pending: '⏸️ Pending'
    };
    return badges[status] || status;
  };

  return (
    <div className="App">
      <header className="App-header">
        <h1>📄 Document Processor</h1>
        <p>Powered by Claude AI</p>
      </header>

      <main className="container">
        <div className="upload-section">
          <div {...getRootProps()} className={`dropzone ${isDragActive ? 'active' : ''}`}>
            <input {...getInputProps()} />
            {uploading ? (
              <p>⏳ Uploading...</p>
            ) : isDragActive ? (
              <p>📂 Drop files here...</p>
            ) : (
              <>
                <p>📤 Drag & drop documents here, or click to select</p>
                <small>Supported: PDF, PNG, JPG, TIFF (max 50MB)</small>
              </>
            )}
          </div>
        </div>

        <div className="documents-section">
          <h2>Recent Documents ({documents.length})</h2>
          <div className="documents-list">
            {documents.length === 0 ? (
              <p className="empty-state">No documents yet. Upload your first document above!</p>
            ) : (
              documents.map((doc) => (
                <div key={doc.id} className="document-card">
                  <div className="document-info">
                    <h3>{doc.fileName}</h3>
                    <p className="status">{getStatusBadge(doc.status)}</p>
                    <p className="meta">
                      Uploaded: {formatDate(doc.uploadDate)} |
                      Size: {(doc.sizeBytes / 1024).toFixed(2)} KB
                    </p>
                  </div>
                  {doc.status === 'completed' && (
                    <button
                      className="view-btn"
                      onClick={() => viewExtractedData(doc.id)}
                    >
                      View Data
                    </button>
                  )}
                </div>
              ))
            )}
          </div>
        </div>

        {extractedData && (
          <div className="modal" onClick={() => setExtractedData(null)}>
            <div className="modal-content" onClick={(e) => e.stopPropagation()}>
              <div className="modal-header">
                <h2>Extracted Data</h2>
                <button className="close-btn" onClick={() => setExtractedData(null)}>×</button>
              </div>
              <div className="modal-body">
                <div className="data-section">
                  <h3>Document Information</h3>
                  <p><strong>Model:</strong> {extractedData.model}</p>
                  <p><strong>Confidence:</strong> {(extractedData.confidence * 100).toFixed(1)}%</p>
                  <p><strong>Extracted:</strong> {formatDate(extractedData.extractedAt)}</p>
                </div>

                <div className="data-section">
                  <h3>Extracted Fields</h3>
                  <pre>{JSON.stringify(extractedData.extractedFields, null, 2)}</pre>
                </div>

                {extractedData.warnings && extractedData.warnings.length > 0 && (
                  <div className="data-section warnings">
                    <h3>⚠️ Warnings</h3>
                    <ul>
                      {extractedData.warnings.map((warning, idx) => (
                        <li key={idx}>{warning}</li>
                      ))}
                    </ul>
                  </div>
                )}

                {extractedData.usage && (
                  <div className="data-section">
                    <h3>Usage Statistics</h3>
                    <p>Input Tokens: {extractedData.usage.input_tokens}</p>
                    <p>Output Tokens: {extractedData.usage.output_tokens}</p>
                  </div>
                )}
              </div>
            </div>
          </div>
        )}
      </main>

      <footer>
        <p>Built with React + Azure Functions + Claude AI</p>
      </footer>
    </div>
  );
}

export default App;
