param networkSecurityGroupName string
param location string = resourceGroup().location
param sqlmiNSGid string

@description('Specifies the Azure tags that will be assigned to the resource.')
param tags object = {
  environment: 'test'
}

resource nsg 'Microsoft.Network/networkSecurityGroups@2020-06-01' = if (empty(sqlmiNSGid)){
  name: networkSecurityGroupName
  location: location
  tags: tags
  properties: {
    securityRules: []
  }
}

output id string = nsg.id
