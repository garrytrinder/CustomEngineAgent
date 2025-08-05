@maxLength(20)
@minLength(4)
@description('Used to generate names for all resources in this file')
param resourceBaseName string

param webAppSKU string

@maxLength(42)
param botDisplayName string

param serverfarmsName string = resourceBaseName
param webAppName string = resourceBaseName
param identityName string = resourceBaseName
param location string = resourceGroup().location

param graphEntraAppClientId string
param graphEntraAppTenantId string
@secure()
param graphEntraAppClientSecret string

resource storageAccount 'Microsoft.Storage/storageAccounts@2022-05-01' = {
  name: '${toLower(replace(resourceBaseName, '-', ''))}state'
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    supportsHttpsTrafficOnly: true
    defaultToOAuthAuthentication: true
  }
}

resource siteConfig 'Microsoft.Web/sites/config@2021-02-01' = {
  name: 'appsettings'
  parent: webApp
  properties: {
    WEBSITE_RUN_FROM_PACKAGE: '1'
    RUNNING_ON_AZURE: '1'
    APPINSIGHTS_INSTRUMENTATIONKEY: applicationInsights.properties.InstrumentationKey
    APPINSIGHTS_PROFILERFEATURE_VERSION: '1.0.0'
    APPINSIGHTS_SNAPSHOTFEATURE_VERSION: '1.0.0'
    APPLICATIONINSIGHTS_CONNECTION_STRING: applicationInsights.properties.ConnectionString
    ApplicationInsightsAgent_EXTENSION_VERSION: '~2'
    DiagnosticServices_EXTENSION_VERSION: '~3'
    InstrumentationEngine_EXTENSION_VERSION: 'disabled'
    SnapshotDebugger_EXTENSION_VERSION: 'disabled'
    XDT_MicrosoftApplicationInsights_BaseExtensions: 'disabled'
    XDT_MicrosoftApplicationInsights_Java: '1'
    XDT_MicrosoftApplicationInsights_Mode: 'recommended'
    XDT_MicrosoftApplicationInsights_NodeJS: '1'
    XDT_MicrosoftApplicationInsights_PreemptSdk: 'disabled'

    // AgentApplication settings
    AgentApplication__StartTypingTimer: 'false'
    AgentApplication__RemoveRecipientMention: 'false'
    AgentApplication__NormalizeMentions: 'false'
    AgentApplication__UserAuthorization__DefaultHandlerName: 'me'
    AgentApplication__UserAuthorization__AutoSignin: 'true'
    AgentApplication__UserAuthorization__Handlers__me__Settings__AzureBotOAuthConnectionName: 'Microsoft Graph'
    AgentApplication__UserAuthorization__Handlers__me__Settings__Title: 'Sign in'
    AgentApplication__UserAuthorization__Handlers__me__Settings__Text: 'Sign in to Microsoft Graph'
    
    // TokenValidation settings
    TokenValidation__Audiences__ClientId: identity.properties.clientId
    TokenValidation__TenantId: identity.properties.tenantId
    
    // Logging settings
    Logging__LogLevel__Default: 'Information'
    'Logging__LogLevel__Microsoft.AspNetCore': 'Warning'
    'Logging__LogLevel__Microsoft.Agents': 'Warning'
    'Logging__LogLevel__Microsoft.Hosting.Lifetime': 'Information'
    
    // BotServiceConnection settings
    Connections__BotServiceConnection__Settings__AuthType: 'UserManagedIdentity'
    Connections__BotServiceConnection__Settings__ClientId: identity.properties.clientId
    Connections__BotServiceConnection__Settings__Scopes__0: 'https://api.botframework.com/.default'
    
    // BlobsStorageOptions settings
    BlobsStorageOptions__ConnectionString: '@Microsoft.KeyVault(VaultName=${keyVault.name};SecretName=storageAccountConnectionString)'
    BlobsStorageOptions__ContainerName: 'state'
  }
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: resourceBaseName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Request_Source: 'rest'
  }
}

resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  location: location
  name: identityName
}

resource serverfarm 'Microsoft.Web/serverfarms@2021-02-01' = {
  kind: 'app'
  location: location
  name: serverfarmsName
  sku: {
    name: webAppSKU
  }
}

resource webApp 'Microsoft.Web/sites@2021-02-01' = {
  kind: 'app'
  location: location
  name: webAppName
  properties: {
    serverFarmId: serverfarm.id
    httpsOnly: true
    keyVaultReferenceIdentity: identity.id
    siteConfig: {
      alwaysOn: true
      ftpsState: 'FtpsOnly'
    }
  }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${identity.id}': {}
    }
  }
}

resource keyVault 'Microsoft.KeyVault/vaults@2021-06-01-preview' = {
  name: resourceBaseName
  location: location
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    accessPolicies: [
      {
        tenantId: subscription().tenantId
        objectId: identity.properties.principalId
        permissions: {
          secrets: ['get', 'list']
        }
      }
    ]
  }
}

resource storageAccountVault 'Microsoft.KeyVault/vaults/secrets@2021-06-01-preview' = {
  parent: keyVault
  name: 'storageAccountConnectionString'
  properties: {
    value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
  }
}

resource graphEntraAppClientSecretVault 'Microsoft.KeyVault/vaults/secrets@2021-06-01-preview' = {
  parent: keyVault
  name: 'graphEntraAppClientSecret'
  properties: {
    value: graphEntraAppClientSecret
  }
}

resource botService 'Microsoft.BotService/botServices@2022-09-15' = {
  kind: 'azurebot'
  location: 'global'
  name: resourceBaseName
  properties: {
    displayName: botDisplayName
    endpoint: 'https://${webApp.properties.defaultHostName}/api/messages'
    msaAppId: identity.properties.clientId
    msaAppTenantId: identity.properties.tenantId
    msaAppType: 'UserAssignedMSI'
    msaAppMSIResourceId: identity.id
    disableLocalAuth: true
  }
  sku: {
    name: 'F0'
  }
}

resource botServiceMsTeamsChannel 'Microsoft.BotService/botServices/channels@2022-09-15' = {
  parent: botService
  location: 'global'
  name: 'MsTeamsChannel'
  properties: {
    channelName: 'MsTeamsChannel'
  }
}

resource botServiceMicrosoftGraphConnection 'Microsoft.BotService/botServices/connections@2022-09-15' = {
  parent: botService
  name: 'Microsoft Graph'
  location: 'global'
  properties: {
    serviceProviderDisplayName: 'Azure Active Directory v2'
    serviceProviderId: '30dd229c-58e3-4a48-bdfd-91ec48eb906c'
    clientId: graphEntraAppClientId
    clientSecret: graphEntraAppClientSecret
    scopes: 'email offline_access openid profile User.Read'
    parameters: [
      {
        key: 'tenantID'
        value: graphEntraAppTenantId
      }
      {
        key: 'tokenExchangeUrl'
        value: 'api://${webApp.properties.defaultHostName}/botid-${identity.properties.clientId}'
      }
    ]
  }
}

output BOT_AZURE_APP_SERVICE_RESOURCE_ID string = webApp.id
output BOT_DOMAIN string = webApp.properties.defaultHostName
output BOT_ID string = identity.properties.clientId
output BOT_TENANT_ID string = identity.properties.tenantId
