param(
    [string]$resourceGroup = "observabilitytest",
    [string]$location = "centralindia",
    [string]$clusterName = "e6obsadxcluster",
    [string]$databaseName = "telemetrydb",
    [string]$eventHubNamespace = "observabilityingestns",
    [string]$eventHubName = "telemetryhub",
    [string]$consumerGroup = "asaconsumer",
    [string]$asaJobName = "telemetryasa",
    [string]$lawName = "observability-law",
    [string]$grafanaName = "observability-grafana"
)

az login

# -----------------------------
# Step 1: Deploy infra with Bicep
# -----------------------------
az group create --name $resourceGroup --location $location

az deployment group create `
  --resource-group $resourceGroup `
  --template-file ../deploy/bicep/infra.bicep `
  --parameters `
    adxCluster=$clusterName `
    adxDb=$databaseName `
    eventHubNamespace=$eventHubNamespace `
    eventHubName=$eventHubName `
    consumerGroupName=$consumerGroup `
    lawName=$lawName `
    asaJobName=$asaJobName

if ($LASTEXITCODE -ne 0) { throw "Bicep deployment failed." }


# -----------------------------
# Step 2: Role Assignments
# -----------------------------
Write-Host "Step 2: Setting up role assignments for ASA..."

# Get ASA system-assigned identity
$asaPrincipalId = az stream-analytics job show `
  --resource-group $resourceGroup `
  --name $asaJobName `
  --query "identity.principalId" -o tsv

$asaAssignment = az kusto database-principal-assignment list `
  --cluster-name $clusterName `
  --database-name $databaseName `
  --resource-group $resourceGroup `
  --query "[?principalId=='$asaPrincipalId' && role=='Admin']" -o tsv

if ([string]::IsNullOrEmpty($asaAssignment)) {
    Write-Host "No ASA Admin assignment found, deploying roleassignment.bicep..."

    # Deploy role assignments
    az deployment group create `
      --resource-group $resourceGroup `
      --template-file ../deploy/bicep/roleassignment.bicep `
      --parameters `
        clusterName=$clusterName `
        databaseName=$databaseName `
        asaPrincipalId=$asaPrincipalId
} else {
    Write-Host "ASA Admin role assignment already exists. Skipping."
}

if ($LASTEXITCODE -ne 0) { throw "Bicep Role Assignment deployment failed." }

# -----------------------------
# Step 3: Configure Diagnostic Settings
# -----------------------------
Write-Host "Step 3: Adding diagnostic settings for Event Hub + ASA to LAW..."
$lawId = az monitor log-analytics workspace show -g $resourceGroup -n $lawName --query id -o tsv
$ehId = az eventhubs namespace show -g $resourceGroup -n $eventHubNamespace --query id -o tsv
$asaId = az stream-analytics job show -g $resourceGroup -n $asaJobName --query id -o tsv

az monitor diagnostic-settings create --name "EventHubToLAW" --resource $ehId --workspace $lawId --metrics '[{"category":"AllMetrics","enabled":true}]'
az monitor diagnostic-settings create --name "ASAToLAW" --resource $asaId --workspace $lawId --metrics '[{"category":"AllMetrics","enabled":true}]'

# -----------------------------
# Step 4: Setup Grafana RBAC
# -----------------------------
Write-Host "Step 4: Creating Grafana service principal + role assignments..."
$sp = az ad sp create-for-rbac --name "$grafanaName-app" --role "Monitoring Reader" --scopes "/subscriptions/$(az account show --query id -o tsv)" -o json
$clientId = ($sp | ConvertFrom-Json).appId
$tenantId = ($sp | ConvertFrom-Json).tenant
$secret = ($sp | ConvertFrom-Json).password
$objectId = ($sp | ConvertFrom-Json).id

# Assign ADX Viewer role
Write-Host "Step 4: Assigning Grafana SP as Viewer on ADX..."
az kusto database-principal-assignment create `
  --cluster-name $clusterName `
  --database-name $databaseName `
  --resource-group $resourceGroup `
  --principal-id $clientId `
  --principal-type App `
  --role Viewer `
  --principal-assignment-name "GrafanaViewer"

# -----------------------------
# Step 5: Start ASA Job
# -----------------------------
echo "Step 5: Starting ASA job $asaJobName..."

az stream-analytics job start `
  --resource-group $resourceGroup `
  --name $asaJobName

if ($LASTEXITCODE -eq 0) {
    echo "ASA job started successfully."
} else {
    throw "Failed to start ASA job."
}

Write-Host "Grafana App registered."
Write-Host "Client ID: $clientId"
Write-Host "Tenant ID: $tenantId"
Write-Host "Secret: $secret"
Write-Host "Object ID: $objectId"
Write-Host "Save these values and configure in Grafana > Data Sources > Azure Monitor"

Write-Host "Deployment and configuration complete."
