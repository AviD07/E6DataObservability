#!/bin/bash
set -euo pipefail

# -----------------------------
# Parameters
# -----------------------------
resourceGroup="observabilitytest"
location="centralindia"
clusterName="e6obsadxcluster"
databaseName="telemetrydb"
eventHubNamespace="observabilityingestns"
eventHubName="telemetryhub"
consumerGroup="asaconsumer"
asaJobName="telemetryasa"
lawName="observability-law"
grafanaName="observability-grafana"

# -----------------------------
# Step 0: Login
# -----------------------------
az login

# -----------------------------
# Step 1: Deploy infra with Bicep
# -----------------------------
az group create --name "$resourceGroup" --location "$location"

az deployment group create \
  --resource-group "$resourceGroup" \
  --template-file ../deploy/bicep/infra.bicep \
  --parameters \
    adxCluster="$clusterName" \
    adxDb="$databaseName" \
    eventHubNamespace="$eventHubNamespace" \
    eventHubName="$eventHubName" \
    consumerGroupName="asaconsumer" \
    lawName="$lawName" \
    asaJobName="$asaJobName"

if [ $? -ne 0 ]; then
  echo "Bicep deployment failed."
  exit 1
fi

# -----------------------------
# Step 2: Role Assignments
# -----------------------------
echo "Step 2: Setting up role assignments for Grafana and ASA..."

asaPrincipalId=$(az stream-analytics job identity show \
  --resource-group "$resourceGroup" \
  --job-name "$asaJobName" \
  --query principalId -o tsv)

asaAssignment=$(az kusto database-principal-assignment list \
  --cluster-name "$clusterName" \
  --database-name "$databaseName" \
  --resource-group "$resourceGroup" \
  --query "[?principalId=='$asaPrincipalId' && role=='Admin']" -o tsv)

if [ -z "$asaAssignment" ]; then
  echo "No ASA Admin assignment found, deploying roleassignment.bicep..."
  az deployment group create \
    --resource-group "$resourceGroup" \
    --template-file ./bicep/roleassignment.bicep \
    --parameters adxClusterName="$clusterName" adxDbName="$databaseName" \
                 asaPrincipalId="$asaPrincipalId" grafanaSpId="$grafanaAppId"
else
  echo "ASA Admin role assignment already exists. Skipping."
fi

# -----------------------------
# Step 2: Configure Diagnostic Settings
# -----------------------------
echo "Step 2: Adding diagnostic settings for Event Hub + ASA to LAW..."
lawId=$(az monitor log-analytics workspace show -g "$resourceGroup" -n "$lawName" --query id -o tsv)
ehId=$(az eventhubs namespace show -g "$resourceGroup" -n "$eventHubNamespace" --query id -o tsv)
asaId=$(az stream-analytics job show -g "$resourceGroup" -n "$asaJobName" --query id -o tsv)

az monitor diagnostic-settings create --name "EventHubToLAW" --resource "$ehId" --workspace "$lawId" --metrics '[{"category":"AllMetrics","enabled":true}]'
az monitor diagnostic-settings create --name "ASAToLAW" --resource "$asaId" --workspace "$lawId" --metrics '[{"category":"AllMetrics","enabled":true}]'

# -----------------------------
# Step 3: Setup Grafana RBAC
# -----------------------------
echo "Step 3: Creating Grafana service principal + role assignments..."
sp=$(az ad sp create-for-rbac --name "$grafanaName-app" --role "Monitoring Reader" --scopes "/subscriptions/$(az account show --query id -o tsv)" -o json)
clientId=$(echo "$sp" | jq -r .appId)
tenantId=$(echo "$sp" | jq -r .tenant)
secret=$(echo "$sp" | jq -r .password)
objectId=$(echo "$sp" | jq -r .id)


# Assign ADX Viewer role
echo "Step 4: Assigning Grafana SP as Viewer on ADX..."
az kusto database-principal-assignment create \
  --cluster-name $clusterName \
  --database-name $databaseName \
  --resource-group $resourceGroup \
  --principal-id $objectId \
  --principal-type App \
  --role Viewer \
  --principal-assignment-name "GrafanaViewer"

# -----------------------------
# Step 4: Start ASA Job
# -----------------------------
echo "Starting ASA job: $ASA_JOB_NAME..."
az stream-analytics job start \
  --resource-group "$RESOURCE_GROUP" \
  --name "$ASA_JOB_NAME"


echo "Grafana App registered."
echo "Client ID: $clientId"
echo "Tenant ID: $tenantId"
echo "Secret: $secret"
echo "Save these values and configure in Grafana > Data Sources > Azure Monitor"

echo "Deployment and configuration complete."
