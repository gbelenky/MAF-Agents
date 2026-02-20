// Diagnostic settings for Azure Bot Service

@description('Name for the diagnostic setting')
param name string

@description('Bot Service resource ID')
param botServiceId string

@description('Log Analytics Workspace ID')
param logAnalyticsWorkspaceId string

resource diagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: name
  scope: botServiceResource
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        category: 'BotRequest'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
  }
}

// Reference to existing bot service
resource botServiceResource 'Microsoft.BotService/botServices@2022-09-15' existing = {
  name: last(split(botServiceId, '/'))
}
