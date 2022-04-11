param location string = resourceGroup().location
param userDefinedRouteName string
param sqlmiUDRid string


@description('Specifies the Azure tags that will be assigned to the resource.')
param tags object = {
  environment: 'test'
}



resource udr 'Microsoft.Network/routeTables@2020-11-01' =  if (empty(sqlmiUDRid)){
  name: userDefinedRouteName
  location: location
  tags: tags
  properties: {
    routes: []
  }
}

output id string = udr.id
