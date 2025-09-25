# E6DataObservability

## Overview
This project demonstrates a telemetry and observability pipeline for E6Data’s analytical query engine, designed to handle **500+ events per second** and make them queryable within **T+20 seconds**.

The solution uses:
- **Azure Event Hubs** – Event ingestion layer
- **Azure Stream Analytics (ASA)** – Transformation and routing
- **Azure Data Explorer (ADX)** – OLAP-optimized analytical store
- **Grafana** – Observability dashboards (via ADX + Azure Monitor)

## Prerequisites
- Azure Subscription with sufficient permissions
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli)
- [Bicep CLI](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/install)
- [Docker](https://docs.docker.com/get-docker/) (for running Event Generator)
- [Grafana](https://grafana.com/grafana/download) (local or hosted)


## Prerequisites
- Azure Subscription with sufficient permissions
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli)
- [Bicep CLI](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/install)
- [Docker](https://docs.docker.com/get-docker/) (for running Event Generator)
- [Grafana](https://grafana.com/grafana/download) (local or hosted)
- jq (for shell script JSON parsing)

---

## Deployment Steps

### 1. Deploy Infrastructure
Run either PowerShell or Bash script from `deploy/` folder.

Run with default values:

#### PowerShell
```powershell
cd deploy
./deploy.ps1
```

#### Bash
```bash
cd deploy
./deploy.sh
```

Deploy has default values set in. If you need to change it, run it as shown below.

#### PowerShell
```powershell
cd deploy
./deploy.ps1 -resourceGroup observabilitytest -location centralindia -clusterName e6obsadxcluster -databaseName telemetrydb -eventHubNamespace observabilityingestns -eventHubName telemetryhub -consumerGroup asaconsumer -asaJobName telemetryasa -lawName observability-law -grafanaName observability-grafana
```

#### Bash
```bash
cd deploy
./deploy.sh -r observabilitytest -l centralindia -c e6obsadxcluster -d telemetrydb -e observabilityingestns -h telemetryhub -g asaconsumer -a telemetryasa -w observability-law -f observability-grafana
```

This provisions:
- Event Hub namespace, hub, consumer group
- Stream Analytics job (with query)
- ADX cluster, database, and ingestion tables
- Log Analytics Workspace
- Diagnostic settings (EH + ASA -> LAW)
- Service principals + RBAC for ASA (Ingestor) and Grafana (Viewer)

### 2. Verify Deployment
- Go to Azure Portal -> **Resource Group**
- Confirm Event Hub, ASA job, ADX cluster, and LAW exist
- Start the ASA job if not already running

---

## Event Generator

- Get the Event hub connection string from azure portal
- EventHub -> Shared Access Policies -> SendAndListenRule -> Primary Key

### Build Docker image
```bash
cd src/EventGenerator
docker build -t event-generator .
```
####  Set the Event Hub parameters
```bash
docker run --rm event-generator steady 100 300 "eventhub connection string" "event hub name"
```

### Run different scenarios
#### Steady Load (100 QPS, 5 min)
```bash
docker run --rm event-generator steady 100 300 "eventhub connection string" "event hub name"
```
#### Burst Load
```bash
docker run --rm event-generator burst 200 60 "eventhub connection string" "event hub name"
```
#### Recovery Scenario
```bash
docker run --rm event-generator recovery 150 120 "eventhub connection string" "event hub name"
```
#### Outage Simulation
```bash
docker run --rm event-generator outage 0 60 "eventhub connection string" "event hub name"
```

### Event Hub Connection
The Event Hub connection string and name can be passed as environment variables or arguments during first run. Subsequent runs will reuse the saved config.

---

## Grafana Setup

1. Open Grafana UI (default http://localhost:3000)
2. Add **Azure Data Explorer** as a data source:
   - Cluster URL: `https://<adxcluster>.centralindia.kusto.windows.net`
   - Database: `telemetrydb`
   - Auth: Use the service principal created in deploy script
3. Add **Azure Monitor** as a data source:
   - Subscription: your Azure subscription
   - Workspace: `observability-law`
   - Auth: Use same Grafana service principal
4. Import dashboards:
   - Import dashboard from ./dashboard/
   - Update the connection on each chart. Edit and close should do.
   - Component Metrics (EH, ASA)
   - Query Metrics (ADX queries)

---