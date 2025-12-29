targetScope = 'resourceGroup'

@description('Location for all resources')
param location string = 'swedencentral'

@description('Name prefix for all resources')
param namePrefix string = 'dev-env'

@description('VM name')
param vmName string = 'vm-dev'

@description('VM size')
param vmSize string = 'Standard_D2s_v6'

@description('SSH public key for authentication')
@secure()
param sshPublicKey string

@description('Allowed source IP addresses for SSH access (CIDR notation)')
param allowedSshIps array = ['0.0.0.0/0'] // Default allows all - CHANGE THIS!

@description('OS disk size in GB')
param osDiskSizeGB int = 64

// Network module
module network 'modules/network.bicep' = {
  name: 'network-deployment'
  params: {
    location: location
    namePrefix: namePrefix
    allowedSshIps: allowedSshIps
  }
}

// VM module
module vm 'modules/vm.bicep' = {
  name: 'vm-deployment'
  params: {
    location: location
    vmName: vmName
    vmSize: vmSize
    sshPublicKey: sshPublicKey
    nicId: network.outputs.nicId
    osDiskSizeGB: osDiskSizeGB
  }
}

// Outputs
output publicIpAddress string = network.outputs.publicIpAddress
output vmName string = vm.outputs.vmName
output sshCommand string = 'ssh -i ~/.ssh/dev_env_key azureuser@${network.outputs.publicIpAddress}'
output resourceGroup string = resourceGroup().name
