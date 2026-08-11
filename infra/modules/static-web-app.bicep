@description('Regiao Azure do Static Web App.')
param location string

@description('Nome do ambiente azd.')
param environmentName string

@description('Nome do Azure Static Web App.')
param staticWebAppName string

@description('Valor da tag azd-service-name (ex.: web, site).')
param serviceName string = 'web'

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
    'azd-service-name': serviceName
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
