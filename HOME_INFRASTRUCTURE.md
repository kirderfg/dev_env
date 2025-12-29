# Home Infrastructure

Personal infrastructure documentation for Raspberry Pis, networking, and remote access.

## Quick Reference

| Device | Location | Access | Services |
|--------|----------|--------|----------|
| spot1 | Home (Kids room) | `ssh spot1` (local) | Raspotify, Pi-hole |
| spot2 | Home (Kitchen) | `ssh spot2` (local) | Raspotify |
| gistviks-pi | Remote (Gistvik) | `ssh gistviks-pi-ts` (Tailscale) | Pi-hole |
| dev-vm | Azure (Sweden Central) | `ssh dev-vm` (internet) | Docker, DevPod |

**Note:** spot1 and spot2 are on our home LAN - SSH keys are configured in WSL on this machine.
gistviks-pi is at a remote location and accessed exclusively via Tailscale VPN.

## Development VM

We also have an Azure Spot VM for container development. See [README.md](README.md) for full details.

| Property | Value |
|----------|-------|
| Host | `dev-vm` |
| IP | `20.91.246.117` |
| User | `azureuser` |
| SSH Key | `~/.ssh/dev_env_key` |
| Region | Sweden Central |
| VM Size | Standard_D4s_v5 (4 vCPU, 16GB RAM) |

```bash
# SSH into dev VM
ssh dev-vm

# Start/stop VM (saves costs)
./scripts/start-vm.sh
./scripts/stop-vm.sh
```

### DevPod Integration

[DevPod](https://devpod.sh) runs devcontainers on the Azure VM while you develop locally.

```bash
# Create workspace from GitHub repo
devpod up github.com/your/repo --provider ssh --provider-option HOST=dev-vm --ide none

# SSH into workspace
devpod ssh your-repo

# With 1Password secrets
devpod up github.com/your/repo --provider ssh --provider-option HOST=dev-vm \
  --ide none --workspace-env OP_SERVICE_ACCOUNT_TOKEN=$(cat ~/.config/dev_env/op_token)
```

See [README.md](README.md) for:
- Full DevPod setup and usage
- 1Password secrets management
- DevContainer templates
- Cost estimates

## Overview

```
┌─────────────────────────────────────────┐      ┌─────────────────────────────┐
│           HOME NETWORK                   │      │    REMOTE (Gistvik)         │
├─────────────────────────────────────────┤      ├─────────────────────────────┤
│                                          │      │                             │
│  ┌──────────────┐    ┌──────────────┐   │      │   ┌─────────────────────┐   │
│  │    spot1     │    │    spot2     │   │      │   │    gistviks-pi      │   │
│  │  Kids room   │    │   Kitchen    │   │      │   ├─────────────────────┤   │
│  ├──────────────┤    ├──────────────┤   │      │   │ • Pi-hole DNS       │   │
│  │ • Raspotify  │    │ • Raspotify  │   │      │   │ • Tailscale         │   │
│  │ • Pi-hole    │    │              │   │      │   └──────────┬──────────┘   │
│  └──────────────┘    └──────────────┘   │      │              │              │
│            ▲                ▲            │      └──────────────│──────────────┘
│            │ SSH (local)    │            │                     │
│            └───────┬────────┘            │                     │ Tailscale VPN
│                    │                     │                     │ (encrypted)
│         ┌─────────────────────┐          │                     │
│         │   WSL Host          │◄─────────│─────────────────────┘
│         │   (This machine)    │          │
│         │   • Tailscale       │          │
│         │   • SSH keys        │──────────│───────────┐
│         │   • DevPod CLI      │          │           │
│         └─────────────────────┘          │           │ SSH (internet)
└──────────────────────────────────────────┘           │
                                                       ▼
                                           ┌───────────────────────┐
                                           │  AZURE (Sweden Central) │
                                           ├───────────────────────┤
                                           │   ┌───────────────┐   │
                                           │   │    dev-vm     │   │
                                           │   ├───────────────┤   │
                                           │   │ • Docker      │   │
                                           │   │ • DevPod      │   │
                                           │   │ • 1Password   │   │
                                           │   └───────────────┘   │
                                           │   Spot VM (cost-opt)  │
                                           └───────────────────────┘
```

## Raspberry Pis

### spot1 (Kids room)

| Property | Value |
|----------|-------|
| Hostname | `spot1.local` |
| User | `spot` |
| Model | Raspberry Pi 3A+ |
| Services | Raspotify, Pi-hole |
| Spotify Name | "Kids room" |

**Services:**
- **Raspotify** - Spotify Connect client (librespot)
- **Pi-hole** - Network-wide ad blocking DNS

### spot2 (Kitchen and Master bedroom)

| Property | Value |
|----------|-------|
| Hostname | `spot2.local` |
| User | `spot` |
| Model | Raspberry Pi 3A+ |
| Services | Raspotify |
| Spotify Name | "Kitchen and Master bedroom" |

**Services:**
- **Raspotify** - Spotify Connect client (librespot)

### gistviks-pi (Remote location)

| Property | Value |
|----------|-------|
| Hostname | `gistviks-pi.local` (local) / `gistviks-pi-ts` (remote) |
| User | `gistvik` |
| Tailscale IP | `100.125.64.83` |
| Services | Pi-hole, Tailscale |
| Web UI | `http://gistviks-pi.local/admin` |

**Services:**
- **Pi-hole** - Network-wide ad blocking DNS
- **Tailscale** - VPN mesh for remote access

## SSH Access

All Pis use SSH key authentication with `~/.ssh/spot_key` (Ed25519 key generated on this WSL machine).

### Home Network (spot1, spot2)

These are on our home LAN and accessed directly via mDNS:

```bash
ssh spot1              # spot1.local - Kids room
ssh spot2              # spot2.local - Kitchen
```

### Remote Location (gistviks-pi)

gistviks-pi is at a separate location (Gistvik) and **only accessible via Tailscale**:

```bash
ssh gistviks-pi-ts     # 100.125.64.83 via Tailscale VPN
```

When on the same local network as gistviks-pi, you can also use:
```bash
ssh gistviks-pi        # gistviks-pi.local (local only)
```

SSH config entries are in `~/.ssh/config`.

## Tailscale

[Tailscale](https://tailscale.com) provides secure remote access to gistviks-pi from anywhere.

### Connected Devices

| Device | Tailscale IP | Purpose |
|--------|--------------|---------|
| gistviks-pi | `100.125.64.83` | Remote Pi-hole |
| WSL Host | `100.83.100.38` | Management |

### Usage

```bash
# Check Tailscale status
tailscale status

# Connect to remote Pi
ssh gistviks-pi-ts

# Run commands remotely
ssh gistviks-pi-ts "sudo pihole -g"   # Update gravity
ssh gistviks-pi-ts "sudo pihole -up"  # Update Pi-hole
```

### Setup (for new devices)

```bash
# Install Tailscale
curl -fsSL https://tailscale.com/install.sh | sudo sh

# Authenticate (opens browser)
sudo tailscale up

# Get IP address
tailscale ip -4
```

## Pi-hole

Network-wide ad blocking DNS server.

### Instances

| Location | Device | Web UI |
|----------|--------|--------|
| Home | spot1 | `http://spot1.local/admin` |
| Remote | gistviks-pi | `http://gistviks-pi.local/admin` |

### Blocklists

Both Pi-holes use the same blocklists:

1. **StevenBlack hosts** - `https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts`
2. **Frellwits Swedish Hosts** - `https://raw.githubusercontent.com/lassekongo83/Frellwits-filter-lists/master/Frellwits-Swedish-Hosts-File.txt`
3. **Perflyst SmartTV** - `https://perflyst.github.io/PiHoleBlocklist/SmartTV.txt`

### Custom Denied Domains

TV4 ad tracking domains (Swedish streaming):
- `tv4-video-tracking.a2d.tv`
- `bumpers.tv4play.se`
- `se-tv4.videoplaza.tv`
- `tv4.video-tracking.a2d.tv`
- `tvm-tv4-freewheel.akamaized.net`

### Common Commands

```bash
# Update blocklists (gravity)
sudo pihole -g

# Update Pi-hole
sudo pihole -up

# Check status
pihole status

# View/add denied domains
sudo pihole deny -l
sudo pihole deny example.com

# View/add allowed domains
sudo pihole allow -l
sudo pihole allow example.com

# Tail DNS query log
pihole -t
```

## Raspotify

[Raspotify](https://github.com/dtcooper/raspotify) runs Spotify Connect (librespot) on Raspberry Pis.

### Configuration

Config file: `/etc/raspotify/conf`

Key setting:
```bash
LIBRESPOT_NAME="Device Name"
```

### Common Commands

```bash
# Restart service
sudo systemctl restart raspotify

# View logs
journalctl -u raspotify -f

# Enable verbose logging (temporary)
sudo sed -i 's/^#LIBRESPOT_VERBOSE=/LIBRESPOT_VERBOSE=/' /etc/raspotify/conf
sudo systemctl restart raspotify
journalctl -u raspotify -f

# Disable verbose logging
sudo sed -i 's/^LIBRESPOT_VERBOSE=/#LIBRESPOT_VERBOSE=/' /etc/raspotify/conf
sudo systemctl restart raspotify
```

## Security

### Authentication Methods

| System | Method |
|--------|--------|
| SSH | Ed25519 key (`~/.ssh/spot_key`) |
| 1Password | Service Account Token |
| Tailscale | SSO via tailscale.com |

### 1Password Integration

See main [README.md](README.md#secrets-management-1password) for 1Password setup details.

Used for:
- Development secrets (API keys, tokens)
- Service account automation
- Credential management

## Maintenance

### Regular Updates

```bash
# Update all packages on a Pi
ssh spot1 "sudo apt update && sudo apt upgrade -y"

# Update Pi-hole
ssh spot1 "sudo pihole -up"

# Update blocklists
ssh spot1 "sudo pihole -g"
```

### Remote Maintenance (gistviks-pi)

```bash
# Connect via Tailscale
ssh gistviks-pi-ts

# Full system update
sudo apt update && sudo apt upgrade -y
sudo pihole -up
sudo pihole -g
```

## Troubleshooting

### SSH Connection Issues

```bash
# Test connectivity
ping spot1.local

# Verbose SSH
ssh -v spot1

# Check if mDNS resolves
avahi-resolve -n spot1.local
```

### Pi-hole Not Blocking

```bash
# Check service status
pihole status

# Verify DNS is listening
sudo ss -tulnp | grep 53

# Test blocking
dig @spot1.local ads.google.com
```

### Raspotify Not Appearing in Spotify

```bash
# Check service
sudo systemctl status raspotify

# View logs for errors
journalctl -u raspotify -n 50

# Restart service
sudo systemctl restart raspotify
```

### Tailscale Connection Issues

```bash
# Check status
tailscale status

# Re-authenticate
sudo tailscale up --reset

# Check if daemon is running
sudo systemctl status tailscaled
```
