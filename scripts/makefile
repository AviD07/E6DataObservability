IMAGE_NAME=azure-deployer

RESOURCE_GROUP ?= avitest
LOCATION ?= centralindia
CLUSTER_NAME ?= adxcluster
DATABASE_NAME ?= telemetrydb
EVENTHUB_NAMESPACE ?= TestObservabilityE6
EVENTHUB_NAME ?= telemetryhub
CONSUMER_GROUP ?= asaconsumer
ASA_JOB_NAME ?= telemetryasa

build:
	docker build -t $(IMAGE_NAME) .

deploy: build
	docker run --rm -it \
		-v $(PWD):/workspace \
		$(IMAGE_NAME) \
		bash -c "az login && \
		az group create --name $(RESOURCE_GROUP) --location $(LOCATION) && \
		az deployment group create \
		  --resource-group $(RESOURCE_GROUP) \
		  --template-file infra.bicep \
		  --parameters \
		    adxDb=$(CLUSTER_NAME) \
		    kustoDatabaseName=$(DATABASE_NAME) \
		    eventHubNamespace=$(EVENTHUB_NAMESPACE) \
		    eventHubName=$(EVENTHUB_NAME) \
		    consumerGroupName=$(CONSUMER_GROUP) \
		    asaJobName=$(ASA_JOB_NAME)"
