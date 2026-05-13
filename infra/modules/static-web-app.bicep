@description('Regiao Azure do Static Web App.')
param location string

@description('Nome do ambiente azd.')
param environmentName string

@description('Nome do Azure Static Web App.')
param staticWebAppName string

@allowed([
  'Free'
  'Standard'
])
@description('SKU do Azure Static Web App.')
param skuName string = 'Free'

resource staticWebApp 'Microsoft.Web/staticSites@2023-12-01' = {
  name: staticWebAppName
  location: location
  tags: {
    'azd-env-name': environmentName
    'azd-service-name': 'web'
  }
  sku: {
    name: skuName
    tier: skuName
  }
  properties: {
    allowConfigFileUpdates: true
  }
}

output name string = staticWebApp.name
output defaultHostname string = staticWebApp.properties.defaultHostname
