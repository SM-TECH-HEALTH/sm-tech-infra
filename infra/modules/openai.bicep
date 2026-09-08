@description('Regiao do Azure OpenAI / Foundry. gpt-4o costuma nao estar em brazilsouth.')
param location string

@description('Nome do ambiente azd.')
param environmentName string

@description('Nome da conta Cognitive Services (OpenAI).')
param accountName string

@description('Subdominio customizado do endpoint (unico globalmente).')
param customSubDomainName string

@description('Nome do deployment (AZURE_OPENAI_DEPLOYMENT).')
param deploymentName string = 'gpt-4o'

@description('Nome do modelo no catalogo Foundry.')
param modelName string = 'gpt-4o'

@description('Versao do modelo.')
param modelVersion string = '2024-08-06'

@description('SKU do deployment (GlobalStandard ou Standard).')
param skuName string = 'GlobalStandard'

@description('Capacidade em milhares de tokens por minuto.')
param capacity int = 10

resource account 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: accountName
  location: location
  sku: {
    name: 'S0'
  }
  kind: 'OpenAI'
  tags: {
    'azd-env-name': environmentName
    'azd-service-name': 'openai'
  }
  properties: {
    customSubDomainName: customSubDomainName
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
  }
}

resource deployment 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
  parent: account
  name: deploymentName
  sku: {
    name: skuName
    capacity: capacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: modelName
      version: modelVersion
    }
  }
}

output endpoint string = account.properties.endpoint
output deploymentName string = deployment.name
output accountName string = account.name
