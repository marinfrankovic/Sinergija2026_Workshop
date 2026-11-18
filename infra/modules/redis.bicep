// Azure Managed Redis B0, non-HA for the workshop. TLS only, port 10000.
// NoCluster preserves the legacy single-endpoint client; access key stays in Key Vault.
param location string
param tags object
param name string
param keyVaultName string

resource redis 'Microsoft.Cache/redisEnterprise@2026-09-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: 'Balanced_B0'
  }
  properties: {
    highAvailability: 'Disabled'
    minimumTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
  }
}

resource database 'Microsoft.Cache/redisEnterprise/databases@2026-09-01' = {
  parent: redis
  name: 'default'
  properties: {
    clientProtocol: 'Encrypted'
    clusteringPolicy: 'NoCluster'
    accessKeysAuthentication: 'Enabled'
    evictionPolicy: 'VolatileLRU'
    port: 10000
  }
}

resource kv 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

resource redisSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: kv
  name: 'redis-password'
  properties: {
    value: database.listKeys().primaryKey
    contentType: 'text/plain'
  }
}

output name string = redis.name
output hostName string = redis.properties.hostName
output sslPort int = database.properties.port
output passwordSecretUri string = redisSecret.properties.secretUri
