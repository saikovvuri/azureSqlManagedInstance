@maxLength(5)
@minLength(2)
param envPrefixName string = toLower('mogas')

param tags object = {
  environment: 'test'
}
param location string = resourceGroup().location

@description('SKU Edition (GeneralPurpose, BusinessCritical)')
param miSkuEdition string = 'GeneralPurpose'

@allowed([
  'GP_Gen4'
  'GP_Gen5'
  'BC_Gen4'
  'BC_Gen5'
])

@description('SKU NAME (GP_Gen4, GP_Gen5, BC_Gen4, BC_GEN5)')
param miSkuName string = 'GP_Gen5'

@allowed([
  'Gen4'
  'Gen5'
])
@description('Hardware family (Gen4, Gen5)')
param miHardwareFamily string = 'Gen5'

@description('Admin user for Managed Instance')
param miAdminLogin string

@description('Amount of Storage in GB for this instance. Minimum value: 32. Maximum value: 8192. Increments of 32 GB allowed only.')
param miStorageSizeInGB int = 32

@allowed([
  4
  8
  16
  24
  32
  40
  64
  80
])
@description('The number of vCores. Allowed values: 4, 8, 16, 24, 32, 40, 64, 80.')
param mivCores int = 4

@allowed([
  'BasePrice'
  'LicenseIncluded'
])
@description('Type of license: BasePrice (BYOL) or LicenceIncluded')
param miLicenseType string = 'BasePrice'
@description('SQL Collation')
param miCollation string = 'SQL_Latin1_General_CP1_CI_AS'

@description('Id of the timezone. Allowed values are timezones supported by Windows. List of Ids can also be obtained by executing [System.TimeZoneInfo]::GetSystemTimeZones() in PowerShell.')
param miTimeZoneId string = 'Pacific Standard Time'

@description('Minimal TLS version. Allowed values: None, 1.0, 1.1, 1.2')
param miMinimalTlsVersion string = '1.2'

@description('The storage account type used to store backups for this instance. The options are LRS (LocallyRedundantStorage), ZRS (ZoneRedundantStorage) and GRS (GeoRedundantStorage). - GRS, LRS, ZRS')
param miStorageAccountType string = 'LRS'

@allowed([
  'Proxy'
  'Redirect'
  'Default'
])
@description('Connection type used for connecting to the instance. - Proxy, Redirect, Default')
param miProxyOverride string = 'Redirect'

// Specify Azure AD Administrator Login
@description('Enable Azure AD Authentication?')
param sqlManagedInstanceEnableAADAuthentication bool = false
@description('AAD Login name of the server administrator') 
param sqlManagedInstanceAdministratorAADLogin string = ''
@description('SID (object ID) of the server administrator')
param sqlManagedInstanceAdministratorAADSID string = ''
@description('Tenant ID of the administrator')
param sqlManagedInstanceAdministratorAADTenantID string = '' 

var miPassword = 'P${uniqueString(resourceGroup().id)}-${uniqueString(subscription().id)}x!'
var resourceGroupName = resourceGroup().name


var vnetName = '${envPrefixName}miVnet'

module vnet 'modules/vnet/vnet.bicep' = {
  name: 'vnetdeployment'
  params: {
    location: location
    virtualNetworkName: vnetName
    addressPrefixes: [
      '10.0.0.0/16'
    ]
    subnets: [
      {   
        name: 'MgmtSubnet'
        prefix: '10.0.0.0/24'
        endpoints: []             
      }
      {   
        name: 'FESubnet'
        prefix: '10.0.1.0/24'
        endpoints: []
                
      }
      {   
        name: 'SvcSubnet'
        prefix: '10.0.2.0/24'
        endpoints: []     
         
      }
      {
        name: 'MISubnet'
        prefix: '10.0.3.0/24'
        endpoints: []        
      }      
    ]
  }
}



// Need a reference to an existing subnet to determine if it's already been delegated to SQL MI
resource subnet 'Microsoft.Network/virtualNetworks/subnets@2020-11-01' existing = {
  name: '${vnetName}/MISubnet'
  scope: resourceGroup(resourceGroupName)  
}

// Retrieve properties of the subnet, like delegation, NSG, and UDR
//var sqlmiSubnetDelegations = !empty(subnet.properties.delegations) ? subnet.properties.delegations[0].properties.serviceName : ''
var sqlmiSubnetNSGid = contains(subnet.properties, 'networkSecurityGroup') ? subnet.properties.networkSecurityGroup.id : ''
var sqlmiSubnetUDRid = contains(subnet.properties, 'routeTable') ? subnet.properties.routeTable.id : ''
var sqlmiSubnetAddressPrefix = subnet.properties.addressPrefix
var sqlManagedInstanceName = '${envPrefixName}sqlmi'

// Determine whether or not to create NSG and UDR
module createSqlMiNSG 'modules/nsg/nsg.bicep' = {
  name: 'createSqlMiNSG'
  dependsOn: [
    subnet
  ]
  params: {
    location: location
    networkSecurityGroupName: '${envPrefixName}miNsg'
    sqlmiNSGid: sqlmiSubnetNSGid
    
  }
}

module createSqlMiUDR 'modules/udr/udr.bicep' = {
  name: 'createSqlMiUDR'
  dependsOn: [
    subnet
  ]
  params: {
    location: location
    userDefinedRouteName: '${envPrefixName}miUdr'
    sqlmiUDRid: sqlmiSubnetUDRid
    
  }
}

module checkSqlMiSubnet 'modules/subnet/subnet.bicep' = {
  name: 'checkSqlMiSubnet'
  scope: resourceGroup(resourceGroupName)
  params: {
    location: location
    sqlmiNSGid: empty(sqlmiSubnetNSGid) ? createSqlMiNSG.outputs.id : sqlmiSubnetNSGid
    sqlmiSubnetAddressPrefix: sqlmiSubnetAddressPrefix
    subnetName: subnet.name
    sqlManagedInstanceName: sqlManagedInstanceName
    sqlmiUDRid: empty(sqlmiSubnetUDRid) ? createSqlMiUDR.outputs.id : sqlmiSubnetUDRid
    setSqlmiSubnetServiceEndpoints: (environment().name == 'AzureCloud') ? true : false
  }
  dependsOn: [
    subnet
  ]  
}

resource sqlmi 'Microsoft.Sql/managedInstances@2021-02-01-preview' = {
  name: sqlManagedInstanceName
  location: location
  tags: tags
  dependsOn: [
    checkSqlMiSubnet
  ]

  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: miSkuName
    tier: miSkuEdition
    family: miHardwareFamily
  }
  properties: {
    administratorLogin: miAdminLogin
    administratorLoginPassword: miPassword
    subnetId: subnet.id
    licenseType: miLicenseType
    vCores: mivCores
    storageSizeInGB: miStorageSizeInGB
    collation: miCollation
    publicDataEndpointEnabled: false
    proxyOverride: miProxyOverride
    timezoneId: miTimeZoneId
    minimalTlsVersion: miMinimalTlsVersion
    storageAccountType: miStorageAccountType
    zoneRedundant: false
  }
}

// Set AAD authentication for SQL MI
// The following isn't going to work due to not having Global Admin Access or Privileged Role Administrator to grant the SQL MI MSI Azure AD Directory Readers role
// See this article --> https://docs.microsoft.com/en-us/azure/azure-sql/database/authentication-aad-directory-readers-role
resource sqlmiAADauthentication 'Microsoft.Sql/managedInstances/administrators@2020-11-01-preview' = if (sqlManagedInstanceEnableAADAuthentication) {
  name: '${sqlmi.name}/ActiveDirectory'
  properties:{
    administratorType: 'ActiveDirectory'
    login: sqlManagedInstanceAdministratorAADLogin
    sid: sqlManagedInstanceAdministratorAADSID
    tenantId: sqlManagedInstanceAdministratorAADTenantID
  }
}


