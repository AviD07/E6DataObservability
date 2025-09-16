param asaJobName string
param location string = resourceGroup().location
param adxClusterUri string
param adxDb string
param eventHubNamespace string
param eventHubName string
param consumerGroupName string = 'asaconsumer'
param asaPolicyName string = 'asa-policy'

resource streamJob 'Microsoft.StreamAnalytics/streamingjobs@2021-10-01-preview' = {
  name: asaJobName
  location: location
  properties: {
    eventsOutOfOrderPolicy: 'Adjust'
    outputErrorPolicy: 'Stop'
    eventsOutOfOrderMaxDelayInSeconds: 0
    eventsLateArrivalMaxDelayInSeconds: 5
    dataLocale: 'en-US'
    compatibilityLevel: '1.2'
    sku: {
        name: 'Standard'
    }
  }
  identity: {
    type: 'SystemAssigned'
  }
}

resource input 'Microsoft.StreamAnalytics/streamingjobs/inputs@2021-10-01-preview' = {
  name: 'telemetryinput'
  parent: streamJob
  properties: {
    type: 'Stream'
    datasource: {
      type: 'Microsoft.ServiceBus/EventHub'
      properties: {
        serviceBusNamespace: eventHubNamespace
        eventHubName: eventHubName
        consumerGroupName: consumerGroupName
        sharedAccessPolicyName: asaPolicyName
        authenticationMode: 'ConnectionString'
        sharedAccessPolicyKey: listKeys(resourceId(
          'Microsoft.EventHub/namespaces/eventhubs/authorizationRules',
          eventHubNamespace,
          eventHubName,
          asaPolicyName
        ), '2022-10-01-preview').primaryKey
      }
    }
    serialization: {
      type: 'Json'
      properties: {
        encoding: 'UTF8'
      }
    }
  }
}

resource outputSink 'Microsoft.StreamAnalytics/streamingjobs/outputs@2021-10-01-preview' = {
  name: 'alleventssink'
  parent: streamJob
  properties: {
    datasource: {
      type: 'Microsoft.Kusto/clusters/databases'
      properties: {
        database: adxDb
        cluster: adxClusterUri
        authenticationMode: 'Msi'
        table: 'sink_output'
      }
    }
  }
}

resource outputError 'Microsoft.StreamAnalytics/streamingjobs/outputs@2021-10-01-preview' = {
  name: 'errorsink'
  parent: streamJob
  properties: {
    datasource: {
      type: 'Microsoft.Kusto/clusters/databases'
      properties: {
        database: adxDb
        cluster: adxClusterUri
        authenticationMode: 'Msi'
        table: 'error_events'
      }
    }
  }
}

resource transformation 'Microsoft.StreamAnalytics/streamingjobs/transformations@2021-10-01-preview' = {
  name: 'transformation'
  parent: streamJob
  properties: {
    streamingUnits: 3
    query: '''
WITH TelemetryEvents AS
(
    SELECT
        query_id,
        event_type,
        query_text,
        metadata.user_id AS user_id,
        metadata.[database] AS database_name,
        metadata.duration_ms AS duration_ms,
        metadata.rows_affected AS rows_affected,
        metadata.error AS error,
        payload,
        System.Timestamp AS ingestion_time,
        CAST(timestamp AS datetime) AS event_time
    FROM telemetryinput
)

SELECT
    query_id,
    event_type,
    query_text,
    user_id,
    database_name,
    duration_ms,
    rows_affected,
    payload,
    event_time,
    ingestion_time
INTO alleventssink
FROM TelemetryEvents
WHERE error IS NULL;

SELECT
    query_id,
    event_type,
    query_text,
    user_id,
    database_name,
    error,
    event_time,
    ingestion_time
INTO errorsink
FROM TelemetryEvents
WHERE error IS NOT NULL;
'''
  }
}

output principalId string = streamJob.identity.principalId