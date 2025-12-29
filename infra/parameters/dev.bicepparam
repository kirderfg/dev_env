using '../main.bicep'

param location = 'swedencentral'
param namePrefix = 'dev-env'
param vmName = 'vm-dev'
param vmSize = 'Standard_D2s_v6'
param osDiskSizeGB = 64

// SSH public key - will be read from file during deployment
// param sshPublicKey = '' // Passed via CLI

// Allowed SSH IPs - UPDATE WITH YOUR IP!
// Get your IP: curl -s ifconfig.me
param allowedSshIps = [
  '0.0.0.0/0' // WARNING: Allows all IPs - replace with your IP/32
]
