param clusterName string
param databaseName string
param asaPrincipalId string

resource cluster 'Microsoft.Kusto/clusters@2023-08-15' existing = {
  name: clusterName
}

resource db 'Microsoft.Kusto/clusters/databases@2023-08-15' existing = {
  name: databaseName
  parent: cluster
}

resource asaIngestorRole 'Microsoft.Kusto/clusters/databases/principalAssignments@2023-08-15' = {
  name: 'asa-ingestor'
  parent: db
  properties: {
    role: 'Admin'
    principalId: asaPrincipalId
    principalType: 'App'
  }
}
