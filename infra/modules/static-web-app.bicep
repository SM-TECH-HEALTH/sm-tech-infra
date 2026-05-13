param location string
param environmentName string
param resourceToken string

@allowed(['Free', 'Standard'])
param skuName string

var siteName = 'stapp-${take(resourceToken, 20)}'

resource staticSite 'Microsoft.Web/staticSites@2023-12-01' = {
  name: siteName
  location: location
  sku: {
    name: skuName
    tier: skuName
  }
  properties: {
    allowConfigFileUpdates: true
  }
  tags: {
    'azd-service-name': 'web'
    'azd-env-name': environmentName
  }
}

output defaultHostname string = staticSite.properties.defaultHostname
output staticSiteName string = staticSite.name
