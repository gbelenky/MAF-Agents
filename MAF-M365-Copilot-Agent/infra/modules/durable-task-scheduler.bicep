// Azure Durable Task Scheduler
@description('Name of the DTS scheduler')
param name string

@description('Location for the resource')
param location string

@description('Name of the task hub')
param taskHubName string = 'default'

@description('Principal ID of the managed identity for role assignments')
param managedIdentityPrincipalId string

@description('Tags for the resource')
param tags object = {}

// Durable Task Scheduler
resource scheduler 'Microsoft.DurableTask/schedulers@2024-10-01-preview' = {
  name: name
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'Dedicated'
      capacity: 1
    }
    ipAllowlist: []
  }
}

// Task Hub
resource taskHub 'Microsoft.DurableTask/schedulers/taskHubs@2024-10-01-preview' = {
  parent: scheduler
  name: taskHubName
  properties: {}
}

// Role assignment - Durable Task Data Contributor for managed identity
// Role ID: 0ad04412-c4d5-4796-b79c-f76d14c8d402 = Durable Task Data Contributor
resource dtsDataContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(scheduler.id, managedIdentityPrincipalId, '0ad04412-c4d5-4796-b79c-f76d14c8d402')
  scope: scheduler
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '0ad04412-c4d5-4796-b79c-f76d14c8d402')
    principalId: managedIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

output id string = scheduler.id
output name string = scheduler.name
output taskHubName string = taskHub.name
output endpoint string = scheduler.properties.endpoint
