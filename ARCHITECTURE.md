# Event-Driven Fault-Tolerant Architecture

## Overview

This infrastructure implements a robust, event-driven, fault-tolerant architecture on Azure, designed for high availability, scalability, and resilience. The architecture follows industry best practices for enterprise applications, including event sourcing, CQRS patterns, and comprehensive disaster recovery capabilities.

## Architecture Components

### 1. **Event Processing Layer**

#### Event Grid
- **System Topics**: Monitors Azure resource events (Storage, Service Bus, etc.)
- **Custom Topics**: Application events and domain events for event sourcing
- **Private Endpoints**: Secure connectivity within VNet
- **Dead Letter Queues**: Automatic handling of failed event deliveries with retry policies

#### Azure Event Hubs
- **Premium Tier**: High-throughput event streaming with zone redundancy
- **Auto-Inflate**: Automatically scales throughput units (up to 10)
- **Capture**: Automatic archival to blob storage for event replay and audit
- **Consumer Groups**: Separate processing pipelines for analytics, real-time, and event store materialization
- **Partitions**: 8-16 partitions for parallel processing

#### Service Bus Premium
- **Queues with Dead Letter Queues**:
  - File Processing Queue
  - Order Processing Queue (with sessions for ordered processing)
  - Notification Queue
  - DLQ Monitor Queue
- **Topics and Subscriptions**: Pub/sub pattern for domain events
- **Features**:
  - Duplicate detection (10-minute window)
  - Message TTL (7-14 days)
  - Zone redundancy
  - Private endpoints

### 2. **Compute Layer**

#### App Service Environment v3 (ASE v3)
- **Zone Redundant**: High availability across availability zones
- **Internal Load Balancing**: Private endpoints only
- **TLS 1.2+**: Encrypted communication
- **Plans**:
  - Elastic Premium (EP1) for Functions with auto-scaling (1-20 instances)
  - Isolated v2 (I1v2) for Web App

#### Azure Functions (.NET 8)
- **Primary Function App**: Main application logic
- **DLQ Processor**: Dedicated function for dead letter queue processing
- **Features**:
  - Pre-warmed instances for low latency
  - VNet integration
  - Managed identity authentication
  - Application Insights monitoring

#### Logic Apps (Standard)
- **Order Workflow**: Complex business process orchestration
- **Error Handler**: Centralized error handling and DLQ processing
- **Notification Orchestrator**: Multi-channel notification management
- **Features**:
  - VNet integration
  - Stateful workflows
  - Built-in retry policies

### 3. **Data Layer**

#### Cosmos DB
- **Multi-Region Replication**: 3 regions (East US 2, West US 2, Central US)
- **Automatic Failover**: High availability with multiple write locations
- **Databases and Containers**:
  - **EventStore Database**:
    - DomainEvents: Event sourcing store with TTL -1 (never expire)
    - Snapshots: Aggregate snapshots (30-day TTL)
    - ReadModels: CQRS read models with optimized indexing
  - **Application Database**:
    - SessionState: User sessions (24-hour TTL)
    - DLQTracking: Failed message tracking (90-day TTL)
    - CircuitBreakerState: Resilience pattern state (24-hour TTL)
- **Features**:
  - Session consistency level
  - Continuous backup
  - Analytical storage for HTAP workloads
  - Zone redundancy in primary and secondary regions

#### Azure Cache for Redis Premium
- **Zone Redundant**: 3 availability zones
- **Clustering**: 3 shards for horizontal scaling
- **Persistence**:
  - RDB snapshots (hourly)
  - AOF (Append-Only File) for durability
  - Geo-redundant backup storage
- **Features**:
  - TLS 1.2+ only
  - Private endpoints
  - Replicas for high availability

#### Storage Accounts
- **Function Storage**: LRS for function runtime
- **Event Store**: GRS with versioning and 90-day retention
- **Logic Apps Storage**: GRS for workflow state
- **Redis Backup**: GRS for cache backups
- **Lifecycle Policies**:
  - Events: Cool tier (30 days), Archive (90 days), Delete (7 years)
  - Telemetry: Cool tier (7 days), Delete (30 days)
  - Audit: Cool (90 days), Archive (1 year), Delete (7 years)

### 4. **Network Layer**

#### Virtual Network (10.0.0.0/16)
- **Subnets**:
  - ASE Subnet (10.0.1.0/24): Delegated to App Service
  - Private Endpoints (10.0.2.0/24): All private endpoints
  - Hybrid Connections (10.0.3.0/24): On-premises SQL connectivity
  - Azure Bastion (10.0.4.0/26): Secure management access
  - Management (10.0.5.0/24): Management VMs
  - Application Gateway (10.0.6.0/24): Regional load balancing

#### Private DNS Zones
- Event Grid: privatelink.eventgrid.azure.net
- Service Bus: privatelink.servicebus.windows.net
- Event Hubs: privatelink.servicebus.windows.net
- Cosmos DB: privatelink.documents.azure.com
- Redis Cache: privatelink.redis.cache.windows.net
- Storage Blob: privatelink.blob.core.windows.net
- ASE: {ase-name}.appserviceenvironment.net

#### Azure Front Door Premium
- **WAF Policy**: OWASP 3.2, Bot protection, Rate limiting
- **Private Link**: Direct connectivity to ASE-hosted apps
- **Health Probes**: 240-second intervals
- **Load Balancing**: Latency-based routing with health monitoring

#### Application Gateway v2 (WAF)
- **Zone Redundant**: 3 availability zones
- **Auto-scaling**: 2-10 instances
- **WAF**: OWASP 3.2 rule set in Prevention mode
- **Health Probes**: 30-second intervals
- **Backend Pools**: Function App and Web App

### 5. **Resilience Patterns**

#### Dead Letter Queue Handling
- **Automatic DLQ Monitoring**: Dedicated function monitors all DLQs
- **Retry Policies**:
  - Exponential backoff with jitter
  - Max 5 retry attempts
  - Configurable delay (1s to 60s)
- **Tracking**: DLQ events stored in Cosmos DB with 90-day retention
- **Alerting**: Alerts trigger when DLQ depth exceeds threshold

#### Circuit Breaker
- **State Management**: Stored in Cosmos DB
- **Configurations**:
  - External API: 5 failures, 60s timeout
  - Database: 3 failures, 30s timeout
- **Half-Open State**: Gradual recovery testing

#### Retry Policies
- **Transient Errors**: 5 attempts, exponential backoff (1s-60s)
- **Rate Limiting**: 3 attempts, exponential backoff (5s-30s)
- **Timeouts**:
  - HTTP: 30 seconds
  - Database: 10 seconds
  - Cache: 5 seconds

#### Bulkhead Isolation
- **Critical Operations**: 100 concurrent, 50 queued
- **Background Jobs**: 20 concurrent, 100 queued

### 6. **Monitoring & Observability**

#### Application Insights
- **Distributed Tracing**: End-to-end transaction tracking
- **Custom Metrics**: Business and performance metrics
- **Live Metrics**: Real-time monitoring

#### Log Analytics Workspace
- **Centralized Logging**: 90-day retention
- **Log Sources**:
  - Function Apps
  - Service Bus
  - Event Hubs
  - Cosmos DB
  - Application Gateway

#### Azure Monitor Alerts
- **Critical Alerts** (PagerDuty + SMS + Email):
  - Function App 5xx errors (>10 in 5 min)
  - Service Bus DLQ growth (>5 messages)
  - ASE health failures
- **Warning Alerts** (Email):
  - Web App response time (>5s average)
  - Event Hub processing lag (>10k messages in 15 min)
  - Cosmos DB high RU consumption (>100k)
  - Redis memory usage (>90%)

#### Auto-scaling
- **Function App**:
  - Scale out: CPU >70% or Memory >80% (add 2 instances)
  - Scale in: CPU <30% (remove 1 instance)
  - Weekend profile: Lower baseline
- **Web App**:
  - Scale out: CPU >75% or Queue >10 (add 1-2 instances)
  - Scale in: CPU <25% (remove 1 instance)
  - Range: 2-10 instances

### 7. **Disaster Recovery**

#### Backup Strategy
- **Recovery Services Vault**: Geo-redundant, soft delete enabled
- **VM Backups**:
  - Daily at 02:00 EST
  - Retention: 30 days, 12 weeks, 12 months, 7 years
- **Storage Backups**:
  - Daily blob backups
  - 90-day retention

#### Multi-Region Failover
- **Cosmos DB**: Active-active in 3 regions with automatic failover
- **Traffic Manager**: Priority-based routing with 30s TTL for fast failover
- **Front Door**: Global load balancing with health-based routing

#### Business Continuity
- **RTO (Recovery Time Objective)**: <1 hour
- **RPO (Recovery Point Objective)**: <15 minutes
- **Event Replay**: Event sourcing enables point-in-time recovery
- **Chaos Engineering**: Azure Chaos Studio targets for resilience testing

## Event Flow

### 1. **Synchronous Request Flow**
```
User → Front Door → Application Gateway → Web App/Function App
                                         ↓
                                    Redis Cache
                                         ↓
                                    Cosmos DB (Read Models)
```

### 2. **Asynchronous Event Processing**
```
Event Source → Event Grid → Service Bus Queue → Function App
                    ↓                              ↓
              Event Hubs ← Domain Event       Process & Store
                    ↓                              ↓
            Capture to Blob              Cosmos DB (Events)
                    ↓                              ↓
              Analytics Pipeline        Update Read Models
```

### 3. **Dead Letter Processing**
```
Failed Message → DLQ → DLQ Monitor Queue → DLQ Processor Function
                                                    ↓
                                            Track in Cosmos DB
                                                    ↓
                                            Retry with backoff
                                                    ↓
                                            Alert if max retries
```

### 4. **Workflow Orchestration**
```
Order Event → Service Bus Topic → Logic App (Order Workflow)
                                        ↓
                        Coordinate: Payment, Inventory, Shipping
                                        ↓
                                Publish Events to Event Hub
                                        ↓
                                Update Cosmos DB
                                        ↓
                        Send Notification via Service Bus
```

## Security Features

- **Network Isolation**: All services use private endpoints
- **Identity**: Managed identities for all Azure-to-Azure authentication
- **Encryption**: TLS 1.2+ for transit, encryption at rest for all data stores
- **WAF**: OWASP protection at both Front Door and Application Gateway
- **DDoS**: Standard DDoS protection on public IPs
- **RBAC**: Least privilege access using built-in roles
- **Secrets**: No connection strings in app settings (use managed identities)

## Cost Optimization

- **Auto-scaling**: Scale down during off-peak hours
- **Lifecycle Management**: Automatic tiering to cool/archive storage
- **Serverless Options**: Cosmos DB supports serverless mode
- **Reserved Instances**: Consider for predictable workloads
- **Storage Tiering**: Automatic archival of old events and logs

## Deployment

### Prerequisites
1. Azure subscription with appropriate permissions
2. Terraform 1.0+
3. Existing Azure Front Door resource
4. On-premises SQL Server connection details (if using hybrid connections)

### Variables
Configure in `terraform.tfvars`:
```hcl
location                     = "East US 2"
environment                  = "production"
app_name                     = "myapp"
existing_front_door_id       = "/subscriptions/.../frontDoorProfiles/..."
management_vm_admin_password = "SecurePassword123!"

on_prem_sql_server = {
  server_name   = "sql.company.local"
  database_name = "AppDB"
  port          = 1433
}
```

### Deployment Steps
```bash
# Initialize Terraform
terraform init

# Review plan
terraform plan

# Deploy infrastructure
terraform apply

# Note: ASE v3 creation takes 60-90 minutes
```

## Operational Runbooks

### DLQ Alert Response
1. Check Azure Monitor for DLQ alert
2. Review DLQ Tracking container in Cosmos DB
3. Analyze failure patterns
4. Manual intervention if systematic issue
5. DLQ Processor automatically retries transient failures

### Failover Procedure
1. Traffic Manager automatically routes to healthy region
2. Monitor Traffic Manager health checks
3. Verify Cosmos DB failover in Azure Portal
4. Test application functionality in failover region

### Scaling Events
1. Auto-scaling handles most scenarios
2. Monitor metrics in Application Insights
3. Adjust auto-scale policies if needed
4. Consider manual scaling for planned events

## Monitoring Dashboards

- **Application Insights**: Real-time application metrics
- **DR Dashboard**: Custom workbook for disaster recovery monitoring
- **Service Health**: Azure Service Health integration
- **Cost Management**: Track infrastructure costs

## Next Steps

1. **Implement Application Code**:
   - Event handlers for Event Grid/Service Bus
   - Circuit breaker and retry logic (Polly library)
   - Event sourcing repositories
   - CQRS read model projections

2. **Configure Alerts**:
   - Update email addresses in action groups
   - Configure PagerDuty webhook
   - Set up SMS notifications

3. **Deploy Secondary Region**:
   - Replicate infrastructure to West US 2
   - Configure Traffic Manager endpoints
   - Enable cross-region VNet peering

4. **Chaos Engineering**:
   - Design chaos experiments
   - Test failover scenarios
   - Validate recovery procedures

5. **Performance Testing**:
   - Load testing with Azure Load Testing
   - Validate auto-scaling policies
   - Optimize Cosmos DB partition strategies

## Support

For questions or issues:
- Review Azure Monitor logs
- Check Application Insights for errors
- Consult Azure documentation
- Contact DevOps team

---
**Last Updated**: 2025-10-06
**Architecture Version**: 1.0
**Terraform Version**: 1.0+
