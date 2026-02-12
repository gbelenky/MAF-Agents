@description('Name of the AI Services resource')
param aiServicesName string

@description('Principal ID of the Managed Identity')
param principalId string

// Reference existing AI Services
resource aiServices 'Microsoft.CognitiveServices/accounts@2024-10-01' existing = {
  name: aiServicesName
}

// Cognitive Services OpenAI Contributor role
// Allows creating agents, threads, runs, etc.
var openAIContributorRoleId = 'a001fd3d-188f-4b5d-821b-7da978bf7442'

resource openAIContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aiServices.id, principalId, openAIContributorRoleId)
  scope: aiServices
  properties: {
    principalId: principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', openAIContributorRoleId)
    principalType: 'ServicePrincipal'
  }
}

// Cognitive Services OpenAI User role (for running agents)
var openAIUserRoleId = '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'

resource openAIUserRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aiServices.id, principalId, openAIUserRoleId)
  scope: aiServices
  properties: {
    principalId: principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', openAIUserRoleId)
    principalType: 'ServicePrincipal'
  }
}

// Cognitive Services User role (general access)
var cognitiveServicesUserRoleId = 'a97b65f3-24c7-4388-baec-2e87135dc908'

resource cognitiveServicesUserRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aiServices.id, principalId, cognitiveServicesUserRoleId)
  scope: aiServices
  properties: {
    principalId: principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', cognitiveServicesUserRoleId)
    principalType: 'ServicePrincipal'
  }
}
