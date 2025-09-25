param adxCluster string
param adxDb string
param location string = resourceGroup().location

resource cluster 'Microsoft.Kusto/clusters@2023-08-15' = {
  name: adxCluster
  location: location
  sku: {
    name: 'Dev(No SLA)_Standard_D11_v2'
    tier: 'Basic'
    capacity: 1
  }
  properties: {
    enableDiskEncryption: true
    enableStreamingIngest: true
    publicNetworkAccess: 'Enabled'
    restrictOutboundNetworkAccess: 'Disabled'
    virtualNetworkConfiguration: null
    engineType: 'V3'
    // zoneRedundant: false
  }
}

resource db 'Microsoft.Kusto/clusters/databases@2023-08-15' = {
  name: '${adxCluster}/${adxDb}'
  kind: 'ReadWrite'
  location: location
  properties: {
    softDeletePeriod: 'P7D'
    hotCachePeriod: 'P1D'
  }
}

resource sinkdb 'Microsoft.Kusto/clusters/databases/scripts@2022-02-01' = {
    name: 'sinktablecreate'
    parent: db
    properties: {
        scriptContent: loadTextContent('../kql/create_sinkevents.kql')
        continueOnErrors: false
    }
}

resource errordb 'Microsoft.Kusto/clusters/databases/scripts@2022-02-01' = {
    name: 'errortablecreate'
    parent: db
    properties: {
        scriptContent: loadTextContent('../kql/create_errorevents.kql')
        continueOnErrors: false
    }
}

output adxClusterId string = cluster.id
output adxDbId string = db.id
