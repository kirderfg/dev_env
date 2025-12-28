@description('Location for all resources')
param location string

@description('Name of the virtual machine')
param vmName string

@description('VM size')
param vmSize string = 'Standard_D4s_v5'

@description('Admin username')
param adminUsername string = 'azureuser'

@description('SSH public key')
@secure()
param sshPublicKey string

@description('Network interface ID')
param nicId string

@description('OS disk size in GB')
param osDiskSizeGB int = 64

// Cloud-init configuration - minimal VM with Docker + shell-bootstrap
var cloudInitConfig = '''
#cloud-config
package_update: true
package_upgrade: true

packages:
  - ca-certificates
  - curl
  - git
  - vim
  - tmux
  - htop
  - jq
  - unzip

runcmd:
  # GitHub CLI (https://github.com/cli/cli/blob/trunk/docs/install_linux.md)
  - curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
  - chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
  - echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null
  # Docker official install (https://docs.docker.com/engine/install/ubuntu/)
  - install -m 0755 -d /etc/apt/keyrings
  - curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  - chmod a+r /etc/apt/keyrings/docker.asc
  - bash -c 'echo -e "Types: deb\nURIs: https://download.docker.com/linux/ubuntu\nSuites: $(. /etc/os-release && echo ${UBUNTU_CODENAME:-$VERSION_CODENAME})\nComponents: stable\nSigned-By: /etc/apt/keyrings/docker.asc" > /etc/apt/sources.list.d/docker.sources'
  - apt-get update
  - apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin gh
  - systemctl enable docker
  - systemctl start docker
  - usermod -aG docker azureuser
  # Git config
  - su - azureuser -c 'git config --global user.name "Fredrik Gustavsson"'
  - su - azureuser -c 'git config --global user.email "fredrik@thegustavssons.se"'
  - su - azureuser -c 'git config --global init.defaultBranch main'
  - su - azureuser -c 'git config --global pull.rebase true'
  # Shell-bootstrap for nice prompt (runs as azureuser)
  - su - azureuser -c 'curl -fsSL https://raw.githubusercontent.com/kirderfg/shell-bootstrap/main/install.sh | bash'
  - echo "VM setup complete" > /var/log/cloud-init-complete.log
'''

// Virtual Machine with Spot configuration
resource vm 'Microsoft.Compute/virtualMachines@2024-03-01' = {
  name: vmName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    priority: 'Spot'
    evictionPolicy: 'Deallocate'
    billingProfile: {
      maxPrice: -1 // Pay up to on-demand price
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: 'ubuntu-24_04-lts'
        sku: 'server'
        version: 'latest'
      }
      osDisk: {
        name: '${vmName}-osdisk'
        createOption: 'FromImage'
        diskSizeGB: osDiskSizeGB
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
        deleteOption: 'Delete'
      }
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: sshPublicKey
            }
          ]
        }
      }
      customData: base64(cloudInitConfig)
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nicId
          properties: {
            deleteOption: 'Delete'
          }
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
      }
    }
  }
}

// Outputs
output vmId string = vm.id
output vmName string = vm.name
