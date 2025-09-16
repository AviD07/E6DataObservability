param eventHubNamespace string
param eventHubName string
param location string = resourceGroup().location
param partitionCount int = 16
param retentionDays int = 7

resource ns 'Microsoft.EventHub/namespaces@2022-10-01-preview' = {
  name: eventHubNamespace
  location: location
  sku: {
    name: 'Standard'
    tier: 'Standard'
    capacity: 4
  }
  properties: {
    isAutoInflateEnabled: true
    maximumThroughputUnits: 10
  }
}

resource eh 'Microsoft.EventHub/namespaces/eventhubs@2022-10-01-preview' = {
  name: '${eventHubNamespace}/${eventHubName}'
  properties: {
    partitionCount: partitionCount
    messageRetentionInDays: retentionDays
  }
}
resource ehAuthRule 'Microsoft.EventHub/namespaces/eventhubs/authorizationRules@2022-10-01-preview' = {
  name: '${eventHubNamespace}/${eventHubName}/SendListenRule'
  properties: {
    rights: [
      'Listen'
      'Send'
    ]
  }
  dependsOn: [
    eh
  ]
}

// Consumer Group
resource consumerGroup 'Microsoft.EventHub/namespaces/eventhubs/consumergroups@2022-10-01-preview' = {
  name: '${eventHubNamespace}/${eventHubName}/asaconsumer'
  properties: {}
  dependsOn: [
    eh
  ]
}

// Shared Access Policy for ASA
resource asaPolicy 'Microsoft.EventHub/namespaces/eventhubs/authorizationRules@2022-10-01-preview' = {
  name: '${eventHubNamespace}/${eventHubName}/asa-policy'
  properties: {
    rights: [
      'Listen'
      'Send'
    ]
  }
  dependsOn: [
    eh
  ]
}

output eventHubConnectionString string = listKeys(ehAuthRule.id, '2022-10-01-preview').primaryConnectionString
output eventHubId string = eh.id
