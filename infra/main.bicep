// =============================================================================
// Ledgerly – Azure landing zone for the workshop (subscription scope).
// Creates rg-ledgerly-<env> and everything inside it.
//   azd env new workshop   ->  rg-ledgerly-workshop in swedencentral
// Always run what-if first:  az deployment sub what-if -l swedencentral -f infra/main.bicep -p infra/main.parameters.json
// (or simply `azd provision --preview`).
// =============================================================================
targetScope = 'subscription'

@minLength(1)
@maxLength(12)
@description('azd environment name. Use "workshop" -> rg-ledgerly-workshop.')
param environmentName string

@description('Azure region for all resources.')
param location string = 'swedencentral'

@description('Object id of the deploying user (azd fills AZURE_PRINCIPAL_ID). Gets Key Vault Secrets Officer + MySQL Entra admin.')
param principalId string = ''

@allowed([
  'User'
  'ServicePrincipal'
])
param principalType string = 'User'

@description('Public IPv4 of the presenter laptop for the MySQL firewall (data migration from on-prem). Empty = no rule.')
param presenterIp string = ''

@secure()
@description('MySQL administrator password (fake workshop value, stored in Key Vault as mysql-admin-password).')
param mysqlAdminPassword string

@description('UPN of the MySQL Microsoft Entra admin (usually the presenter, same identity as principalId). Empty = skip Entra admin.')
param mysqlEntraAdminLogin string = ''

@description('Images pushed by azd deploy / hook. Empty = public placeholder image (first provision).')
param webImage string = ''
param apiImage string = ''
param batchImage string = ''

@description('Tag values')
param owner string = 'workshop-presenter'
param costCenter string = 'CC-4711-WORKSHOP'

var workload = 'ledgerly'
// short, deterministic suffix for globally unique names
var suffix = take(uniqueString(subscription().id, environmentName, location), 5)

var tags = {
  owner: owner
  environment: environmentName
  costCenter: costCenter
  workload: workload
}

// Naming convention: <type>-ledgerly-[<component>-]<env>[-<suffix>]
var names = {
  resourceGroup: 'rg-${workload}-${environmentName}'
  logAnalytics: 'log-${workload}-${environmentName}'
  appInsights: 'appi-${workload}-${environmentName}'
  appIdentity: 'id-${workload}-${environmentName}'
  mysqlIdentity: 'id-${workload}-mysql-${environmentName}'
  registry: 'cr${workload}${replace(environmentName, '-', '')}${suffix}' // alphanumeric only
  keyVault: 'kv-${workload}-${suffix}'                                   // max 24 chars
  mysql: 'mysql-${workload}-${environmentName}-${suffix}'
  redis: 'redis-${workload}-${environmentName}-${suffix}'
  containerEnv: 'cae-${workload}-${environmentName}'
  webApp: 'ca-${workload}-web-${environmentName}'
  apiApp: 'ca-${workload}-api-${environmentName}'
  batchJob: 'caj-${workload}-batch-${environmentName}'
}

var mysqlAdminLogin = 'ledgerlyadmin'
var mysqlDatabaseName = 'ledgerly'

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: names.resourceGroup
  location: location
  tags: union(tags, { 'azd-env-name': environmentName })
}

module monitoring 'modules/monitoring.bicep' = {
  name: 'monitoring'
  scope: rg
  params: {
    location: location
    tags: tags
    logAnalyticsName: names.logAnalytics
    appInsightsName: names.appInsights
  }
}

module identity 'modules/identity.bicep' = {
  name: 'identity'
  scope: rg
  params: {
    location: location
    tags: tags
    appIdentityName: names.appIdentity
    mysqlIdentityName: names.mysqlIdentity
  }
}

module registry 'modules/registry.bicep' = {
  name: 'registry'
  scope: rg
  params: {
    location: location
    tags: tags
    name: names.registry
    pullPrincipalId: identity.outputs.appIdentityPrincipalId
  }
}

module keyvault 'modules/keyvault.bicep' = {
  name: 'keyvault'
  scope: rg
  params: {
    location: location
    tags: tags
    name: names.keyVault
    appPrincipalId: identity.outputs.appIdentityPrincipalId
    adminPrincipalId: principalId
    adminPrincipalType: principalType
    mysqlAdminPassword: mysqlAdminPassword
  }
}

module mysql 'modules/mysql.bicep' = {
  name: 'mysql'
  scope: rg
  params: {
    location: location
    tags: tags
    name: names.mysql
    administratorLogin: mysqlAdminLogin
    administratorPassword: mysqlAdminPassword
    databaseName: mysqlDatabaseName
    presenterIp: presenterIp
    serverIdentityId: identity.outputs.mysqlIdentityId
    entraAdminLogin: mysqlEntraAdminLogin
    entraAdminObjectId: principalId
    logAnalyticsWorkspaceId: monitoring.outputs.logAnalyticsId
  }
}

module redis 'modules/redis.bicep' = {
  name: 'redis'
  scope: rg
  params: {
    location: location
    tags: tags
    name: names.redis
    keyVaultName: keyvault.outputs.name
  }
}

module containerapps 'modules/containerapps.bicep' = {
  name: 'containerapps'
  scope: rg
  dependsOn: [
    registry   // AcrPull must exist before the apps pull from ACR
    keyvault   // Secrets User role for the UAMI
  ]
  params: {
    location: location
    tags: tags
    environmentName: names.containerEnv
    webAppName: names.webApp
    apiAppName: names.apiApp
    batchJobName: names.batchJob
    logAnalyticsName: monitoring.outputs.logAnalyticsName
    appInsightsConnectionString: monitoring.outputs.appInsightsConnectionString
    identityId: identity.outputs.appIdentityId
    identityClientId: identity.outputs.appIdentityClientId
    registryServer: registry.outputs.loginServer
    mysqlPasswordSecretUri: keyvault.outputs.mysqlPasswordSecretUri
    redisPasswordSecretUri: redis.outputs.passwordSecretUri
    mysqlFqdn: mysql.outputs.fqdn
    mysqlAdminLogin: mysqlAdminLogin
    databaseName: mysqlDatabaseName
    redisHost: redis.outputs.hostName
    redisSslPort: redis.outputs.sslPort
    webImage: webImage
    apiImage: apiImage
    batchImage: batchImage
  }
}

// ---- outputs (azd writes these into .azure/<env>/.env) ----
output AZURE_LOCATION string = location
output AZURE_TENANT_ID string = tenant().tenantId
output AZURE_RESOURCE_GROUP string = rg.name
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = registry.outputs.loginServer
output AZURE_CONTAINER_REGISTRY_NAME string = registry.outputs.name
output AZURE_CONTAINER_ENVIRONMENT_NAME string = containerapps.outputs.environmentName
output AZURE_KEY_VAULT_NAME string = keyvault.outputs.name
output AZURE_KEY_VAULT_ENDPOINT string = keyvault.outputs.uri
output AZURE_LOG_ANALYTICS_NAME string = monitoring.outputs.logAnalyticsName
output AZURE_LOG_ANALYTICS_WORKSPACE_ID string = monitoring.outputs.logAnalyticsCustomerId
output APPLICATIONINSIGHTS_NAME string = monitoring.outputs.appInsightsName
output MANAGED_IDENTITY_NAME string = identity.outputs.appIdentityName
output MANAGED_IDENTITY_CLIENT_ID string = identity.outputs.appIdentityClientId
output MYSQL_SERVER_NAME string = mysql.outputs.name
output MYSQL_SERVER_FQDN string = mysql.outputs.fqdn
output MYSQL_ADMIN_LOGIN string = mysqlAdminLogin
output MYSQL_DATABASE_NAME string = mysqlDatabaseName
output REDIS_NAME string = redis.outputs.name
output REDIS_HOST string = redis.outputs.hostName
output WEB_APP_NAME string = names.webApp
output API_APP_NAME string = names.apiApp
output BATCH_JOB_NAME string = names.batchJob
output WEB_URI string = 'https://${containerapps.outputs.webFqdn}'
