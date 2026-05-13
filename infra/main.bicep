targetScope = 'resourceGroup'

@minLength(1)
@maxLength(64)
@description('Nome do ambiente azd (usado em naming e tags).')
param environmentName string

@description('Região do resource group / recursos regionais.')
param location string = resourceGroup().location

@allowed(['dev', 'prod'])
@description('dev: PostgreSQL 32 GB e HA Disabled. prod: armazenamento maior; HA continua Disabled com SKU Burstable B1ms.')
param environmentType string

@description('Opcional: principalId injetado pelo azd para RBAC futura.')
param principalId string = ''

@description('Nome da base de dados PostgreSQL.')
param databaseName string = 'smtech'

@description('Login administrador PostgreSQL (evite nomes reservados).')
param postgresAdminLogin string = 'smtechpgadmin'

@secure()
@description('Palavra-passe do administrador PostgreSQL.')
param postgresAdminPassword string

var resourceToken = toLower(uniqueString(subscription().id, resourceGroup().id, environmentName, location))

module postgres 'modules/postgres.bicep' = {
  name: 'postgres'
  params: {
    location: location
    environmentName: environmentName
    environmentType: environmentType
    databaseName: databaseName
    administratorLogin: postgresAdminLogin
    administratorLoginPassword: postgresAdminPassword
  }
}

var staticWebSku = environmentType == 'dev' ? 'Free' : 'Standard'

module staticWeb 'modules/static-web-app.bicep' = {
  name: 'staticweb'
  params: {
    location: location
    environmentName: environmentName
    resourceToken: resourceToken
    skuName: staticWebSku
  }
}

module containerApps 'modules/container-apps.bicep' = {
  name: 'containerapps'
  params: {
    location: location
    environmentName: environmentName
    environmentType: environmentType
    resourceToken: resourceToken
    postgresHost: postgres.outputs.postgresHost
    postgresDb: postgres.outputs.postgresDatabaseName
    postgresUser: postgres.outputs.postgresAdminUser
    postgresPassword: postgresAdminPassword
    serviceName: 'api'
  }
}

output POSTGRES_HOST string = postgres.outputs.postgresHost
output POSTGRES_DB string = postgres.outputs.postgresDatabaseName
output POSTGRES_USER string = postgres.outputs.postgresAdminUser
@secure()
output POSTGRES_PASSWORD string = postgresAdminPassword

output AZURE_CONTAINER_REGISTRY_ENDPOINT string = containerApps.outputs.containerRegistryLoginServer
output AZURE_CONTAINER_REGISTRY_NAME string = containerApps.outputs.containerRegistryName
output API_URL string = containerApps.outputs.containerAppUrl
output STATIC_WEB_APP_DEFAULT_HOSTNAME string = staticWeb.outputs.defaultHostname
output STATIC_WEB_APP_NAME string = staticWeb.outputs.staticSiteName
