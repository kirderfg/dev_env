# Azure Spot VM Development Environment

A cost-effective Azure Spot VM for container development in Sweden Central.

## Specs

| Component | Value |
|-----------|-------|
| VM Size | Standard_D4s_v5 (4 vCPU, 16GB RAM) |
| OS | Ubuntu 24.04 LTS |
| Disk | 64GB Premium SSD |
| Region | Sweden Central |
| Spot Config | maxPrice: -1 (pay up to on-demand, evict on capacity only) |
| Eviction | Deallocate (preserves disk) |

## Cost Estimate

- Spot VM: ~$0.05/hr
- Disk: ~$10/mo
- Public IP: ~$3.65/mo
- **Total (24/7)**: ~$50/mo
- **Total (8hr/day)**: ~$25/mo

## Prerequisites

- [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) installed
- Azure subscription with permissions to create VMs

## Quick Start

```bash
# 1. Login to Azure
az login

# 2. Deploy the VM (generates SSH key automatically)
./scripts/deploy.sh

# 3. Connect via SSH
./scripts/ssh-connect.sh
```

## Scripts

| Script | Description |
|--------|-------------|
| `deploy.sh` | Deploy/update infrastructure, auto-generates SSH key |
| `ssh-connect.sh` | SSH into the VM |
| `start-vm.sh` | Start a deallocated VM |
| `stop-vm.sh` | Stop and deallocate VM (saves compute costs) |

## After Eviction

If Azure reclaims the VM due to capacity:

```bash
# Check VM status
az vm show -g rg-dev-env -n vm-dev --query "powerState" -o tsv

# Restart the VM
./scripts/start-vm.sh
```

The disk is preserved, so all your data remains intact.

## Security

- SSH key authentication only (no passwords)
- NSG restricts SSH to your IP address
- All other inbound traffic denied

## Pre-installed Tools

The VM comes with:
- Docker & docker-compose
- Git, curl, vim, tmux, htop, jq

## File Structure

```
dev_env/
├── infra/
│   ├── main.bicep              # Main orchestration
│   ├── modules/
│   │   ├── vm.bicep            # Spot VM definition
│   │   └── network.bicep       # VNet, NSG, Public IP
│   └── parameters/
│       └── dev.bicepparam      # Environment parameters
├── scripts/
│   ├── deploy.sh
│   ├── ssh-connect.sh
│   ├── start-vm.sh
│   └── stop-vm.sh
└── README.md
```

## Cleanup

To delete all resources:

```bash
az group delete --name rg-dev-env --yes --no-wait
```
