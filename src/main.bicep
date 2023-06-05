param location string = resourceGroup().location

@description('Storage Account to use as persistence layer')
param storageAccountName string = 'sqs${substring(uniqueString(resourceGroup().id), 0, 8)}'

@description('Container Instance to use as SonarQube host')
param containerInstanceName string = 'sq-container'

@description('DNS name for the SonarQube instance')
param dnsName string = 'sq${substring(uniqueString(resourceGroup().id), 0, 8)}'

@description('Azure SQL Server Name to use for SonarQube')
param sqlServerName string = 'sqsvr${substring(uniqueString(resourceGroup().id), 0, 4)}'

@description('Azure SQL Database to use for SonarQube')
param sqlDatabaseName string = 'sonarqube-db'

@description('Database login for SonarQube')
param sqlServerAdminLogin string = 'sonar'

@description('Database password for SonarQube')
@secure()
param sqlServerAdminPassword string

resource sonarqubeStorageAccount 'Microsoft.Storage/storageAccounts@2021-04-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties:{
    accessTier: 'Hot'
  }
}

resource defaultConfFileShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2022-09-01' = {
  name: '${storageAccountName}/default/conf'
  dependsOn: [
    sonarqubeStorageAccount
  ]
}

resource defaultDataFileShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2022-09-01' = {
  name: '${storageAccountName}/default/data'
  dependsOn: [
    sonarqubeStorageAccount
  ]
}

resource defaultExtensionsFileShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2022-09-01' = {
  name: '${storageAccountName}/default/extensions'
  dependsOn: [
    sonarqubeStorageAccount
  ]
}

resource defaultLogsFileShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2022-09-01' = {
  name: '${storageAccountName}/default/logs'
  dependsOn: [
    sonarqubeStorageAccount
  ]
}


resource sonarqubeSqlServer 'Microsoft.Sql/servers@2022-08-01-preview' ={
  name: sqlServerName
  location: location
  properties:{
    administratorLogin: sqlServerAdminLogin
    administratorLoginPassword:sqlServerAdminPassword
  }
}

resource firewallRule 'Microsoft.Sql/servers/firewallRules@2022-08-01-preview' ={
  name: 'AzureServices'
  parent:sonarqubeSqlServer
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

resource sonarSqlDatabase 'Microsoft.Sql/servers/databases@2022-08-01-preview' = {
  name:sqlDatabaseName
  location: location
  parent:sonarqubeSqlServer
  sku: {
    name: 'Basic'
    tier: 'Basic'
  }
  properties: {
    collation: 'SQL_Latin1_General_CP1_CS_AS'
    maxSizeBytes: 2147483648 // 2 GB
  }
}

resource sonarqubeContainer 'Microsoft.ContainerInstance/containerGroups@2021-07-01' = {
  name: containerInstanceName
  location: location
  properties: {
    containers: [
      {
        name: 'sonarqube-container'
        properties: {
          image: 'sonarqube:latest'
          environmentVariables: [
            {
              name: 'SONAR_JDBC_PASSWORD'
              value: sqlServerAdminPassword
            }
            {
              name: 'SONAR_JDBC_URL'
              value: 'jdbc:sqlserver://${sqlServerName}.database.windows.net:1433;database=${sqlDatabaseName};encrypt=true;trustServerCertificate=false;hostNameInCertificate=*.database.windows.net;loginTimeout=30;'
            }
            {
              name: 'SONAR_JDBC_USERNAME'
              value: sqlServerAdminLogin
            }
          ]
          volumeMounts: [
            {
              name: 'conf'
              mountPath: '/opt/sonarqube/conf'
            }
            {
              name: 'data'
              mountPath: '/opt/sonarqube/data'
            }
            {
              name: 'extensions'
              mountPath: '/opt/sonarqube/extensions'
            }
            {
              name: 'logs'
              mountPath: '/opt/sonarqube/logs'
            }
          ]
          resources: {
            requests: {
              cpu: 2
              memoryInGB: 8
            }
          }
          ports: [
            {
              port: 9000
              protocol: 'TCP'
            }
            {
              port: 80
              protocol: 'TCP'
            }
          ]
        }
      }
    ]
    osType: 'Linux'
    ipAddress: {
      type: 'Public'
      dnsNameLabel: dnsName
      ports: [
        {
          protocol: 'TCP'
          port: 9000
        }
      ]
    }
    restartPolicy: 'OnFailure'
    volumes: [
      {
        name: 'conf'
        azureFile: {
          shareName: 'conf'
          storageAccountName: storageAccountName
          storageAccountKey: sonarqubeStorageAccount.listKeys().keys[0].value
          readOnly: false
        }
      }
      {
        name: 'data'
        azureFile: {
          shareName: 'data'
          storageAccountName: storageAccountName
          storageAccountKey: sonarqubeStorageAccount.listKeys().keys[0].value
          readOnly: false
        }
      }
      {
        name: 'extensions'
        azureFile: {
          shareName: 'extensions'
          storageAccountName: storageAccountName
          storageAccountKey: sonarqubeStorageAccount.listKeys().keys[0].value
          readOnly: false
        }
      }
      {
        name: 'logs'
        azureFile: {
          shareName: 'logs'
          storageAccountName: storageAccountName
          storageAccountKey: sonarqubeStorageAccount.listKeys().keys[0].value
          readOnly: false
        }
      }
    ]
  }
  dependsOn:[
    sonarqubeSqlServer
  ]
}



