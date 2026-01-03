# PRD: Task Master Integration for Dev Environment

## Overview
Integrate Task Master AI into the dev environment infrastructure to provide AI-powered task management capabilities across both the Azure VM (dev-vm) and all DevPod containers.

## Goals
1. Enable Task Master MCP server on dev-vm for Claude Code users
2. Pre-install Task Master in all DevPod containers via devcontainer template
3. Ensure Node.js is available in all environments
4. Provide consistent task management experience across the development workflow

## Requirements

### 1. Dev-VM Setup
- **Node.js Installation**: Install Node.js 20.x on dev-vm via NodeSource repository
- **MCP Configuration**: Configure Task Master as MCP server in `~/.claude/.mcp.json`
- **Automation**: Add Node.js installation to `setup-vm.sh` script for new VM deployments

### 2. DevPod Container Setup
- **Base Image Update**: Ensure devcontainer template includes Node.js (already included via Python+Node image)
- **Task Master Pre-install**: Add `task-master-ai` npm package to devcontainer postCreate
- **MCP Config**: Include Task Master MCP config in container's Claude Code settings

### 3. Shell-Bootstrap Integration
- **Optional**: Consider adding Task Master CLI aliases to shell-bootstrap for quick access
- **Environment Variables**: Ensure any required env vars are set in both contexts

## Technical Implementation

### Phase 1: Dev-VM (Already Complete)
- [x] Install Node.js 20.x on dev-vm
- [x] Create `~/.claude/.mcp.json` with taskmaster-ai config
- [ ] Update `setup-vm.sh` to include Node.js installation

### Phase 2: DevContainer Template Updates
- [ ] Update `devcontainer.json` to include Node.js feature (if not present)
- [ ] Add `postCreateCommand` to install task-master-ai globally
- [ ] Add `.mcp.json` template for Claude Code in containers
- [ ] Test deployment with new devpod

### Phase 3: Documentation
- [ ] Update CLAUDE.md with Task Master usage instructions
- [ ] Add pet snippets for common Task Master commands

## Files to Modify

### dev_env repository
| File | Change |
|------|--------|
| `scripts/setup-vm.sh` | Add Node.js installation step |
| `CLAUDE.md` | Add Task Master documentation section |
| `pet-snippets-devenv.toml` | Add Task Master snippets |

### devcontainer-template repository
| File | Change |
|------|--------|
| `devcontainer.json` | Add postCreateCommand for task-master-ai |
| `.claude/.mcp.json` | New file - MCP server config for containers |

## Success Criteria
1. `npx task-master-ai --help` works on dev-vm
2. Task Master MCP tools available in Claude Code on dev-vm
3. New devpod deployments have Task Master pre-installed
4. Task Master MCP tools available in Claude Code inside devpods

## Out of Scope
- API key management for Task Master (uses Claude Code CLI session)
- Custom Task Master configuration per project
- Task Master web UI integration
