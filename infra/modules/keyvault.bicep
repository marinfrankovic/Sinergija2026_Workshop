// Key Vault (RBAC mode). UAMI -> Key Vault Secrets User, presenter -> Key Vault Secrets Officer.
param location string
param tags object
param name string
param appPrincipalId string
param adminPrincipalId string = ''
param adminPrincipalType string = 'User'
@secure()
param mysqlAdminPassword string

var secretsUserRoleId = '4633458b-17de-408a-b874-0445c86b69e6'
var secretsOfficerRoleId = 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7'

resource kv 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    tenantId: subscription().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    publicNetworkAccess: 'Enabled' // workshop: Container Apps (Consumption, no VNet) reads secrets over the public endpoint
  }
}

resource mysqlSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: kv
  name: 'mysql-admin-password'
  properties: {
    value: mysqlAdminPassword
    contentType: 'text/plain'
  }
}

resource appSecretsUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(kv.id, appPrincipalId, secretsUserRoleId)
  scope: kv
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', secretsUserRoleId)
    principalId: appPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource adminSecretsOfficer 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(adminPrincipalId)) {
  name: guid(kv.id, adminPrincipalId, secretsOfficerRoleId)
  scope: kv
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', secretsOfficerRoleId)
    principalId: adminPrincipalId
    principalType: adminPrincipalType
  }
}

output name string = kv.name
output uri string = kv.properties.vaultUri
output mysqlPasswordSecretUri string = mysqlSecret.properties.secretUri
