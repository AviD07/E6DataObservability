# E6Data Telemetry and Observability

## Problem Statement
Design and implement a telemetry and observability pipeline that:

1. Ingests high-volume query events in real-time  
2. Transforms and stores these events in an OLAP-optimized format  
3. Ensures events are queryable within **T+20 seconds** (where T = event generation time)  
4. Handles the specified load sustainably  

### Context
E6Data's analytical query engine processes SQL queries continuously with the following characteristics:

- **Query Processing Rate**: ~100 queries/sec  
- **P95 Latency**: ~2 seconds per query  
- **Event Generation**: Each query produces ~5 events  
- **Event Size**: 1-5 KB per event  
- **Business Requirement**: Events must be queryable within **20s** of generation  

---

## Functional Requirements
- Ingest and process ** >= 500 events/sec **  
- Store data in **columnar / OLAP format** (for analytics)  
- Data available for queries within **20s of event generation**  
- Support analytical queries: aggregations, time-series, filtering  
- Handle out-of-order arrivals  
- Ensure **no data loss** under normal operations  

## Non-Functional Requirements
- **Horizontally scalable** architecture  
- **Fault tolerance** for single-component failures  
- Observability into system health & performance  
- Efficient resource usage  
- **Clear separation of concerns**  

---

## Design Discussions

### Assumptions
- **Data Generator**: Simple app producing events -> not fault-tolerant.  
- **Retry Handling**: Managed by the Query Processor Engine (QPE).  
- **Timestamps**: Marked correctly at generation time.  
- **Delivery Guarantees**: *At-least-once* -> duplicates possible, must be deduplicated downstream.  
- **Schema Changes**: Expected and should be handled.  

### Failure Handling
- **QPE failures** -> No telemetry or delayed telemetry. Recovery: local buffering or secondary sink.  
- **Telemetry ingestion failures** -> Retries and backpressure handling in Event Hub + ASA.  
- **System-level failures** -> Recovery via checkpoints and scaling.  

### Delivery Target
- **P95 latency <20s** across the entire pipeline.  

---

## Architecture

### Option 1: Event Hub -> ADX
- Direct streaming ingest from Event Hub to Azure Data Explorer.  

Pros:  
- Low latency, minimal moving parts, cost-efficient.  
- Meets T+20s easily with streaming ingest.  

Cons:  
- No transformation or enrichment.  
- Limited flexibility for filtering / joins / enrichment.  

---

### Option 2: Event Hub -> Stream Analytics (ASA) -> ADX
- ASA as a transformation and routing layer.  
- Events split into **two tables**:  
  - `sink_output`: all normal events  
  - `error_events`: error-only events  

Pros:  
- Real-time enrichment, filtering, de-duplication.  
- Can write to multiple sinks (ADX, cold storage, dashboards).  
- Better observability and fault-tolerance.  

Cons:  
- Slightly higher cost.  
- Adds ~5-10s latency.  

---

### Option 3: Hybrid (Cloud + Local)
- **Cloud**: EH -> ASA -> ADX  
- **Local**: Kafka -> Flink -> Clickhouse  
- Can act as failover or separate critical vs. non-critical telemetry.  

For this implementation, **Option 2 (cloud-based)** is chosen.  

---

## Data Model and Schema

### Incoming Event
```json
{
  "query_id": "unique_identifier",
  "timestamp": "ISO-8601 timestamp",
  "event_type": "enumerated_type",
  "query_text": "actual SQL query",
  "metadata": {
    "user_id": "string",
    "database": "string",
    "duration_ms": "number",
    "rows_affected": "number",
    "error": "optional_error_details"
  },
  "payload": "event_specific_data"
}
```

### ADX Tables
- **`sink_output`** (normal events):  
  - query_id (string)  
  - event_type (string)  
  - query_text (string)  
  - user_id (string)  
  - database_name (string)  
  - duration_ms (long)  
  - rows_affected (long)  
  - payload (string)  
  - event_time (datetime)  
  - ingestion_time (datetime)  

- **`error_events`** (error events):  
  - query_id (string)  
  - event_type (string)  
  - query_text (string)  
  - user_id (string)  
  - database_name (string)  
  - error (string)  
  - event_time (datetime)  
  - ingestion_time (datetime)  

---

## Transformation Layer (ASA)
- Splits data into **sink_output** and **error_events**.  
- Handles:  
  - Event ordering  
  - Late arrivals (via watermarking)  
  - De-duplication  

ASA Query (simplified):  
```sql
WITH TelemetryEvents AS (
  SELECT
    query_id, event_type, query_text,
    metadata.user_id AS user_id,
    metadata.[database] AS database_name,
    metadata.duration_ms, metadata.rows_affected, metadata.error,
    payload, System.Timestamp AS ingestion_time,
    CAST(timestamp AS datetime) AS event_time
  FROM telemetryinput
)

SELECT ... INTO sink_output FROM TelemetryEvents WHERE error IS NULL;
SELECT ... INTO error_events FROM TelemetryEvents WHERE error IS NOT NULL;
```

---

## Scalability Considerations
- **Event Hub**:  
  - 4 TU baseline (1 MB/s ingress per TU).  
  - 16 partitions for parallelism.  
  - Scale up TU during spikes.  

- **Stream Analytics**:  
  - 3 Streaming Units (SUs).  
  - Watermark delay observed: ~10s.  
  - Scale SU during recovery spikes.  

- **Azure Data Explorer**:  
  - Dev SKU (`Standard_D11_v2`).  
  - Auto-scales at higher SKUs.  
  - Cold-starts may cause latency spikes initially.  

---

## Failure & Recovery
- **QPE Failure** -> buffer locally, retry later.  
- **Event Hub Failure** -> retry on producer, scale TU to mitigate throttling.  
- **ASA Failure** -> restart from checkpoint, scale SU.  
- **ADX Failure** -> optionally write to blob or secondary OLAP store.  

---

## Observability
- **Dashboard 1: Component Health**  
  - EH metrics: incoming requests, throttling.  
  - ASA metrics: watermark delay, SU utilization.  
  - ADX metrics: ingestion latency, cache hit ratio.  

- **Dashboard 2: QPE Metrics**  
  - Query volume trends.  
  - Error rate over time.  
  - Duration and rows processed.  

Both integrated into **Grafana** via Log Analytics Workspace + ADX plugin.  

---

## Cost Estimate (Monthly, Approx.)
| Component        | Config                          | Cost (USD)  |
|------------------|---------------------------------|-------------|
| **Event Hub**    | 2 TU, standard tier             | $20-50      |
| **Stream Analytics** | 2 SU x 720 hrs              | ~$256 (CInd)|
| **ADX Compute**  | Dev cluster small (2 vCores)    | $200-400    |
| **ADX Storage**  | 7-day hot cache + retention     | $50-100     |
| **Monitoring**   | Logs, networking                | $10-30      |
| **Total**        | ~**$600/month**                 |             |

---

## Conclusion
- Chosen architecture: **Event Hub -> ASA -> ADX**  
- Meets latency requirement of **<20s P95**  
- Provides flexibility for enrichment and error tracking  
- Scales independently at each layer  
- Integrated observability with Grafana  
