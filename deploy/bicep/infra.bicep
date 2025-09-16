targetScope = 'resourceGroup'

@description('Event Hub namespace name')
param eventHubNamespace string

@description('Event Hub name')
param eventHubName string

@description('ADX Cluster name')
param adxCluster string

@description('ADX Database name')
param adxDb string

@description('ASA Job name')
param asaJobName string

@description('Log Analytics Workspace name')
param lawName string

@description('Consumer Group name')
param consumerGroupName string

param location string = resourceGroup().location

module eh 'ingesteventhub.bicep' = {
  name: 'eventHubDeployment'
  params: {
    eventHubNamespace: eventHubNamespace
    eventHubName: eventHubName
    location: location
  }
}

module adx 'dataexplorer.bicep' = {
  name: 'adxDeployment'
  params: {
    adxCluster: adxCluster
    adxDb: adxDb
    location: location
  }
}

var adxClusterUri = 'https://${adxCluster}.${location}.kusto.windows.net'

module asa 'streamanalytics.bicep' = {
  name: 'asaDeployment'
  params: {
    asaJobName: asaJobName
    location: location
    eventHubNamespace: eventHubNamespace
    eventHubName: eventHubName
    adxClusterUri: adxClusterUri
    adxDb: adxDb
    consumerGroupName: consumerGroupName
    asaPolicyName: 'asa-policy'
  }
}

module law 'loganalytics.bicep' = {
  name: 'lawDeployment'
  params: {
    lawName: lawName
    location: location
  }
}
