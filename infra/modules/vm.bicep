@description('Location for all resources')
param location string

@description('Name of the virtual machine')
param vmName string

@description('VM size')
param vmSize string = 'Standard_D2s_v6'

@description('Admin username')
param adminUsername string = 'azureuser'

@description('SSH public key')
@secure()
param sshPublicKey string

@description('Network interface ID')
param nicId string

@description('OS disk size in GB')
param osDiskSizeGB int = 64

@description('Tailscale auth key for automatic connection')
@secure()
param tailscaleAuthKey string = ''

@description('Tailscale API key for removing old devices')
@secure()
param tailscaleApiKey string = ''

// Cloud-init configuration - minimal VM with Docker + shell-bootstrap
// If tailscale auth key provided, add it as a base64-encoded file to avoid YAML escaping issues
var tailscaleAuthKeyBase64 = tailscaleAuthKey == '' ? '' : base64(tailscaleAuthKey)
var tailscaleApiKeyBase64 = tailscaleApiKey == '' ? '' : base64(tailscaleApiKey)

// Build the write_files entries for Tailscale keys
var tailscaleFilesPlaceholder = tailscaleAuthKey == '' ? '' : '  - path: /tmp/tailscale-auth-key\n    encoding: b64\n    content: ${tailscaleAuthKeyBase64}\n    permissions: \'0600\'${tailscaleApiKey == '' ? '' : '\n  - path: /tmp/tailscale-api-key\n    encoding: b64\n    content: ${tailscaleApiKeyBase64}\n    permissions: \'0600\''}'

// Build the runcmd for Tailscale setup (delete old device if API key available, then register)
// Uses jq to properly parse JSON and find devices with hostname starting with "dev-vm"
// (Tailscale appends tailnet suffix, e.g., "dev-vm.tailnet-name.ts.net")
var tailscaleSetupCmd = tailscaleAuthKey == '' ? '' : '- |\n    if [ -f /tmp/tailscale-api-key ]; then\n      API_KEY=$(cat /tmp/tailscale-api-key)\n      DEVICE_IDS=$(curl -s -H "Authorization: Bearer $API_KEY" "https://api.tailscale.com/api/v2/tailnet/-/devices" | jq -r \'.devices[] | select(.hostname == "dev-vm" or (.name | startswith("dev-vm."))) | .id\')\n      for DEVICE_ID in $DEVICE_IDS; do\n        echo "Removing old dev-vm device: $DEVICE_ID"\n        curl -s -X DELETE -H "Authorization: Bearer $API_KEY" "https://api.tailscale.com/api/v2/device/$DEVICE_ID"\n        sleep 1\n      done\n      rm -f /tmp/tailscale-api-key\n    fi\n    sudo tailscale up --authkey="$(cat /tmp/tailscale-auth-key)" --ssh --hostname=dev-vm\n    rm -f /tmp/tailscale-auth-key'

var cloudInitConfig = tailscaleAuthKey == '' ? cloudInitConfigBase : replace(replace(cloudInitConfigBase, '# TAILSCALE_AUTH_FILE_PLACEHOLDER', tailscaleFilesPlaceholder), '# TAILSCALE_AUTH_PLACEHOLDER', tailscaleSetupCmd)

var cloudInitConfigBase = '''
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
  - gpg

write_files:
  - path: /etc/apt/sources.list.d/1password.sources
    content: |
      Types: deb
      URIs: https://downloads.1password.com/linux/debian/amd64
      Suites: stable
      Components: main
      Signed-By: /usr/share/keyrings/1password-archive-keyring.gpg
  - path: /etc/apt/sources.list.d/github-cli.list
    content: |
      deb [arch=amd64 signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main
  - path: /etc/apt/sources.list.d/tailscale.list
    content: |
      deb [signed-by=/usr/share/keyrings/tailscale-archive-keyring.gpg] https://pkgs.tailscale.com/stable/ubuntu noble main
  - path: /tmp/setup-docker-repo.sh
    permissions: '0755'
    content: |
      #!/bin/bash
      . /etc/os-release
      CODENAME="${UBUNTU_CODENAME:-$VERSION_CODENAME}"
      cat > /etc/apt/sources.list.d/docker.sources << EOF
      Types: deb
      URIs: https://download.docker.com/linux/ubuntu
      Suites: $CODENAME
      Components: stable
      Signed-By: /etc/apt/keyrings/docker.asc
      EOF
# TAILSCALE_AUTH_FILE_PLACEHOLDER

runcmd:
  # 1Password CLI keyring
  - curl -fsSL https://downloads.1password.com/linux/keys/1password.asc | gpg --dearmor -o /usr/share/keyrings/1password-archive-keyring.gpg
  - chmod go+r /usr/share/keyrings/1password-archive-keyring.gpg
  # GitHub CLI keyring
  - curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
  - chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
  # Tailscale keyring
  - curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/noble.noarmor.gpg -o /usr/share/keyrings/tailscale-archive-keyring.gpg
  - chmod go+r /usr/share/keyrings/tailscale-archive-keyring.gpg
  # Docker keyring and repo
  - install -m 0755 -d /etc/apt/keyrings
  - curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  - chmod a+r /etc/apt/keyrings/docker.asc
  - /tmp/setup-docker-repo.sh
  # Install packages
  - apt-get update
  - apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin gh 1password-cli tailscale
  - systemctl enable docker
  - systemctl start docker
  - usermod -aG docker azureuser
  # Enable Tailscale
  - systemctl enable tailscaled
  - systemctl start tailscaled
  # Authenticate with Tailscale (placeholder replaced if auth key provided)
  # TAILSCALE_AUTH_PLACEHOLDER
  # Git config
  - su - azureuser -c 'git config --global user.name "Fredrik Gustavsson"'
  - su - azureuser -c 'git config --global user.email "fredrik@thegustavssons.se"'
  - su - azureuser -c 'git config --global init.defaultBranch main'
  - su - azureuser -c 'git config --global pull.rebase true'
  # DevPod CLI
  - curl -L -o /tmp/devpod "https://github.com/loft-sh/devpod/releases/latest/download/devpod-linux-amd64"
  - install -m 0755 /tmp/devpod /usr/local/bin/devpod
  - rm -f /tmp/devpod
  # Add Docker provider to DevPod for azureuser
  - su - azureuser -c 'devpod provider add docker --silent 2>/dev/null || true'
  # Shell-bootstrap for nice prompt (runs as azureuser)
  # NOTE: Must download first then run - piping to bash breaks interactive prompts
  # Secrets will be loaded later via 1Password when setup-vm.sh is run
  - su - azureuser -c 'curl -fsSL https://raw.githubusercontent.com/kirderfg/shell-bootstrap/main/install.sh -o /tmp/shell-bootstrap-install.sh && SHELL_BOOTSTRAP_NONINTERACTIVE=1 bash /tmp/shell-bootstrap-install.sh && rm -f /tmp/shell-bootstrap-install.sh'
  - echo "VM setup complete" > /var/log/cloud-init-complete.log
'''

// Virtual Machine (regular pricing - no eviction)
resource vm 'Microsoft.Compute/virtualMachines@2024-03-01' = {
  name: vmName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
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
