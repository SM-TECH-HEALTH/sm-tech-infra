targetScope = 'resourceGroup'

@description('Nome do ambiente azd, por exemplo dev ou prod.')
param environmentName string

@description('Regiao Azure dos recursos.')
param location string = resourceGroup().location

@description('Regiao do Azure Static Web App. SWA nao esta disponivel em todas as regioes.')
param staticWebAppLocation string = 'eastus2'

@allowed([
  'dev'
  'prod'
])
@description('Tipo do ambiente para diferenciar escala e SKU.')
param environmentType string = 'dev'

@secure()
@minLength(12)
@description('Senha do administrador do PostgreSQL Flexible Server.')
param postgresAdminPassword string

@secure()
@minLength(32)
@description('Chave usada pela API para emitir/validar JWT.')
param jwtSecretKey string

@description('Origem CORS principal. Quando vazio, usa a URL default do Static Web App.')
param corsAllowedOrigin string = ''

@description('Imagem inicial do Container App. O pipeline troca para ghcr.io apos o primeiro provision.')
param initialContainerImage string = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'

var resourceToken = uniqueString(subscription().id, resourceGroup().id, environmentName)
var namePrefix = toLower('smtech-${environmentName}')
var postgresAdministratorLogin = 'smtechadmin'
var postgresDatabaseName = 'SmTechHospital'

module postgres 'modules/postgres.bicep' = {
  name: 'postgres'
  params: {
    location: location
    environmentName: environmentName
    serverName: take('${replace(namePrefix, '-', '')}pg${resourceToken}', 63)
    databaseName: postgresDatabaseName
    administratorLogin: postgresAdministratorLogin
    administratorLoginPassword: postgresAdminPassword
    environmentType: environmentType
  }
}

module web 'modules/static-web-app.bicep' = {
  name: 'static-web-app'
  params: {
    location: staticWebAppLocation
    environmentName: environmentName
    staticWebAppName: take('${namePrefix}-web-${resourceToken}', 60)
    serviceName: 'web'
    skuName: environmentType == 'prod' ? 'Standard' : 'Free'
  }
}

// Site institucional: so em prod, sempre Free (dominio custom suportado no Free).
module site 'modules/static-web-app.bicep' = if (environmentType == 'prod') {
  name: 'static-web-app-site'
  params: {
    location: staticWebAppLocation
    environmentName: environmentName
    staticWebAppName: take('${namePrefix}-site-${resourceToken}', 60)
    serviceName: 'site'
    skuName: 'Free'
  }
}

var postgresConnectionString = 'Host=${postgres.outputs.host};Port=5432;Database=${postgres.outputs.databaseName};Username=${postgres.outputs.administratorLogin};Password=${postgresAdminPassword};SSL Mode=Require;Trust Server Certificate=true;Pooling=true;'
var effectiveCorsAllowedOrigin = empty(corsAllowedOrigin) ? 'https://${web.outputs.defaultHostname}' : corsAllowedOrigin

module api 'modules/container-apps.bicep' = {
  name: 'container-apps'
  params: {
    location: location
    environmentName: environmentName
    environmentType: environmentType
    containerAppName: take('${namePrefix}-api-${resourceToken}', 32)
    containerAppsEnvironmentName: take('${namePrefix}-cae-${resourceToken}', 60)
    initialContainerImage: initialContainerImage
    postgresConnectionString: postgresConnectionString
    jwtSecretKey: jwtSecretKey
    corsAllowedOrigin: effectiveCorsAllowedOrigin
  }
}

output API_CONTAINER_APP_NAME string = api.outputs.containerAppName
output API_URI string = api.outputs.apiUri
output WEB_URI string = 'https://${web.outputs.defaultHostname}'
output SITE_URI string = environmentType == 'prod' ? 'https://${site!.outputs.defaultHostname}' : ''

output POSTGRES_HOST string = postgres.outputs.host
output POSTGRES_DB string = postgres.outputs.databaseName
output POSTGRES_USER string = postgres.outputs.administratorLogin
@secure()
output POSTGRES_PASSWORD string = postgresAdminPassword
