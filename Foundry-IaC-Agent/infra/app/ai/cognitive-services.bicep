@description('Azure region of the deployment')
param location string

@description('Tags to add to the resources')
param tags object

@description('AI services name')
param aiServicesName string

@description('The chat model name to deploy')
param chatModelName string = 'gpt-4.1-mini'

@description('The chat model format')
param chatModelFormat string = 'OpenAI'

@description('The chat model SKU name')
param chatModelSkuName string = 'GlobalStandard'

@description('The chat model capacity')
param chatModelCapacity int = 100

resource aiServices 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' = {
  name: aiServicesName
  location: location
  tags: tags
  sku: {
    name: 'S0'
  }
  kind: 'AIServices'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    customSubDomainName: toLower(aiServicesName)
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
    allowProjectManagement: true
  }
}

resource chatModelDeployment 'Microsoft.CognitiveServices/accounts/deployments@2025-04-01-preview' = {
  parent: aiServices
  name: chatModelName
  sku: {
    name: chatModelSkuName
    capacity: chatModelCapacity
  }
  properties: {
    model: {
      format: chatModelFormat
      name: chatModelName
    }
  }
}

// AI Foundry Project (subresource of AIServices account)
// This is required for using Azure AI Foundry Agent Service (Standard Agents)
resource aiFoundryProject 'Microsoft.CognitiveServices/accounts/projects@2025-06-01' = {
  parent: aiServices
  name: 'iacAgentProject'
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    displayName: 'IaC Agent Project'
    description: 'AI Foundry project for IaC-based agent lifecycle management'
  }
}

// Azure AI User role - required for the project's managed identity to perform agent operations
// Role ID: 53ca6127-db72-4b80-b1b0-d745d6d5456d
var azureAIUserRoleId = '53ca6127-db72-4b80-b1b0-d745d6d5456d'

// Assign Azure AI User role to the project's managed identity on the AI Services account
resource projectManagedIdentityRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aiServices.id, aiFoundryProject.id, azureAIUserRoleId)
  scope: aiServices
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', azureAIUserRoleId)
    principalId: aiFoundryProject.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

output aiServicesName string = aiServices.name
output aiServicesId string = aiServices.id
output aiServicesEndpoint string = aiServices.properties.endpoint

output azureOpenAIServiceEndpoint string = 'https://${aiServices.properties.customSubDomainName}.openai.azure.com/'
output chatDeploymentName string = chatModelDeployment.name

// Output the AI Foundry project endpoint for PersistentAgentsClient
// Format: https://<account-name>.services.ai.azure.com/api/projects/<project-name>
output aiFoundryProjectEndpoint string = 'https://${aiServices.properties.customSubDomainName}.services.ai.azure.com/api/projects/${aiFoundryProject.name}'
output aiFoundryProjectName string = aiFoundryProject.name
output aiFoundryProjectId string = aiFoundryProject.id
