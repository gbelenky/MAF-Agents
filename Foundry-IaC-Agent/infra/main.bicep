targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the environment which is used to generate a short unique hash used in all resources.')
param environmentName string

@minLength(1)
@description('Primary location for all resources')
@allowed(['eastus2', 'swedencentral', 'australiaeast', 'northcentralus'])
@metadata({
  azd: {
    type: 'location'
  }
})
param location string

@description('Optional numeric suffix for resource names. Auto-generated if not provided.')
param nameSuffix string = ''

@description('Id of the user or app to assign application roles')
param principalId string = ''

param resourceGroupName string = ''
param aiServicesName string = ''

@allowed(['gpt-4o-mini', 'gpt-4.1-mini', 'gpt-4o'])
param chatModelName string = 'gpt-4.1-mini'

import * as regionSelector from './app/util/region-selector.bicep'
var abbrs = loadJsonContent('./abbreviations.json')

// Auto-generate suffix if not provided
var autoSuffix = toLower(take(uniqueString(subscription().id, environmentName, location), 8))
var actualSuffix = !empty(nameSuffix) ? nameSuffix : autoSuffix

// Base name for all resources
var resourceToken = 'foundryagent'

var tags = { 'azd-env-name': environmentName }

// Organize resources in a resource group
resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: !empty(resourceGroupName) ? resourceGroupName : '${abbrs.resourcesResourceGroups}${environmentName}'
  location: location
  tags: tags
}

// Azure AI Services with Foundry Project
module aiServices './app/ai/cognitive-services.bicep' = {
  name: 'aiServices'
  scope: rg
  params: {
    location: regionSelector.getAiServicesRegion(location, chatModelName)
    tags: tags
    chatModelName: chatModelName
    aiServicesName: !empty(aiServicesName) ? aiServicesName : '${abbrs.cognitiveServicesAccounts}${resourceToken}-${actualSuffix}'
  }
}

// Assign Cognitive Services OpenAI User role to the developer (for local development and agent management)
var CognitiveServicesOpenAIUser = '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'
module openaiRoleAssignmentDeveloper 'app/rbac/openai-access.bicep' = if (!empty(principalId)) {
  name: 'openaiRoleAssignmentDeveloper'
  scope: rg
  params: {
    openAIAccountName: aiServices.outputs.aiServicesName
    roleDefinitionId: CognitiveServicesOpenAIUser
    principalId: principalId
    principalType: 'User'
  }
}

// ==================================
// Outputs
// ==================================
@description('Name of the resource group.')
output AZURE_RESOURCE_GROUP string = rg.name

@description('Endpoint for Azure OpenAI services.')
output AZURE_OPENAI_ENDPOINT string = aiServices.outputs.azureOpenAIServiceEndpoint

@description('AI Foundry project endpoint for Agent Service.')
output PROJECT_ENDPOINT string = aiServices.outputs.aiFoundryProjectEndpoint

@description('AI Foundry project name.')
output PROJECT_NAME string = aiServices.outputs.aiFoundryProjectName

@description('Chat model deployment name.')
output CHAT_MODEL_DEPLOYMENT string = aiServices.outputs.chatDeploymentName

@description('Azure AI Services name.')
output AI_SERVICES_NAME string = aiServices.outputs.aiServicesName
