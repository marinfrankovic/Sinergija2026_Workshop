// Container Apps environment + web (external), api (internal), batch (scheduled job).
// First provision runs public placeholder images; `azd deploy` (web, api) and the
// postdeploy hook (batch) replace them with the real images from ACR.
param location string
param tags object
param environmentName string
param webAppName string
param apiAppName string
param batchJobName string
param logAnalyticsName string
param appInsightsConnectionString string
param identityId string
param identityClientId string
param registryServer string
param mysqlPasswordSecretUri string
param redisPasswordSecretUri string
param mysqlFqdn string
param mysqlAdminLogin string
param databaseName string
param redisHost string
param redisSslPort int
param webImage string = ''
param apiImage string = ''
param batchImage string = ''

var placeholderImage = 'mcr.microsoft.com/k8se/quickstart:latest'
var placeholderJobImage = 'mcr.microsoft.com/k8se/quickstart-jobs:latest'
var apiIsPlaceholder = empty(apiImage)

var userIdentity = {
  type: 'UserAssigned'
  userAssignedIdentities: {
    '${identityId}': {}
  }
}

var registries = [
  {
    server: registryServer
    identity: identityId
  }
]

// Key Vault references resolved by Container Apps with the UAMI
var dbPasswordSecret = {
  name: 'db-password'
  keyVaultUrl: mysqlPasswordSecretUri
  identity: identityId
}
var redisPasswordSecret = {
  name: 'redis-password'
  keyVaultUrl: redisPasswordSecretUri
  identity: identityId
}

resource law 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: logAnalyticsName
}

resource cae 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: environmentName
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics' // -> ContainerAppConsoleLogs_CL / ContainerAppSystemLogs_CL
      logAnalyticsConfiguration: {
        customerId: law.properties.customerId
        sharedKey: law.listKeys().primarySharedKey
      }
    }
    zoneRedundant: false
  }
}

resource api 'Microsoft.App/containerApps@2024-03-01' = {
  name: apiAppName
  location: location
  tags: union(tags, { 'azd-service-name': 'api' })
  identity: userIdentity
  properties: {
    managedEnvironmentId: cae.id
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: false        // internal only – reachable from web inside the environment
        targetPort: 8080
        transport: 'http'
        allowInsecure: true    // nginx calls http://<api app name> inside the environment
      }
      registries: registries
      secrets: [
        dbPasswordSecret
        redisPasswordSecret
      ]
    }
    template: {
      containers: [
        {
          name: 'api'
          image: apiIsPlaceholder ? placeholderImage : apiImage
          resources: {
            cpu: json('1.0')
            memory: '2Gi'
          }
          env: [
            { name: 'DB_HOST', value: mysqlFqdn }
            { name: 'DB_PORT', value: '3306' }
            { name: 'DB_NAME', value: databaseName }
            { name: 'DB_USER', value: mysqlAdminLogin }
            { name: 'DB_PASSWORD', secretRef: 'db-password' }
            { name: 'DB_SSL_MODE', value: 'REQUIRED' }
            { name: 'REDIS_HOST', value: redisHost }
            { name: 'REDIS_PORT', value: string(redisSslPort) }
            { name: 'REDIS_PASSWORD', secretRef: 'redis-password' }
            { name: 'REDIS_SSL', value: 'true' }
            { name: 'AZURE_CLIENT_ID', value: identityClientId }
            { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: appInsightsConnectionString }
          ]
          // Probes only for the real image (the placeholder does not serve /api/health on 8080).
          probes: apiIsPlaceholder ? [] : [
            {
              type: 'Startup'
              httpGet: { path: '/api/health', port: 8080 }
              initialDelaySeconds: 10
              periodSeconds: 5
              timeoutSeconds: 10
              failureThreshold: 30
            }
            {
              type: 'Liveness'
              httpGet: { path: '/api/health', port: 8080 }
              periodSeconds: 15
              timeoutSeconds: 10
              failureThreshold: 3
            }
            {
              type: 'Readiness'
              httpGet: { path: '/api/health', port: 8080 }
              periodSeconds: 10
              timeoutSeconds: 10
              failureThreshold: 3
            }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 5
        rules: [
          {
            name: 'http-50-concurrent'
            http: {
              metadata: {
                concurrentRequests: '50'
              }
            }
          }
        ]
      }
    }
  }
}

resource web 'Microsoft.App/containerApps@2024-03-01' = {
  name: webAppName
  location: location
  tags: union(tags, { 'azd-service-name': 'web' })
  identity: userIdentity
  properties: {
    managedEnvironmentId: cae.id
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: true          // public HTTPS endpoint (TLS terminated by Container Apps)
        targetPort: 80
        transport: 'auto'
        allowInsecure: false
      }
      registries: registries
    }
    template: {
      containers: [
        {
          name: 'web'
          image: empty(webImage) ? placeholderImage : webImage
          resources: {
            cpu: json('0.25')
            memory: '0.5Gi'
          }
          env: [
            { name: 'API_UPSTREAM', value: 'http://${api.name}' }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 3
      }
    }
  }
}

resource batch 'Microsoft.App/jobs@2024-03-01' = {
  name: batchJobName
  location: location
  tags: tags // not an azd service – updated by scripts/hooks/postdeploy-batch.ps1
  identity: userIdentity
  properties: {
    environmentId: cae.id
    configuration: {
      triggerType: 'Schedule'
      replicaTimeout: 600
      replicaRetryLimit: 1
      scheduleTriggerConfig: {
        cronExpression: '*/15 * * * *'
        parallelism: 1
        replicaCompletionCount: 1
      }
      registries: registries
      secrets: [
        dbPasswordSecret
      ]
    }
    template: {
      containers: [
        {
          name: 'batch'
          image: empty(batchImage) ? placeholderJobImage : batchImage
          resources: {
            cpu: json('0.25')
            memory: '0.5Gi'
          }
          env: [
            { name: 'RUN_ONCE', value: 'true' }
            { name: 'DB_HOST', value: mysqlFqdn }
            { name: 'DB_PORT', value: '3306' }
            { name: 'DB_NAME', value: databaseName }
            { name: 'DB_USER', value: mysqlAdminLogin }
            { name: 'DB_PASSWORD', secretRef: 'db-password' }
            { name: 'DB_SSL', value: 'true' }
          ]
        }
      ]
    }
  }
}

output environmentName string = cae.name
output environmentId string = cae.id
output webFqdn string = web.properties.configuration.ingress.fqdn
output apiInternalFqdn string = api.properties.configuration.ingress.fqdn
