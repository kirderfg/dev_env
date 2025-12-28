#!/bin/bash
# Security scanning script
# Run: ./security-scan.sh [quick|full]

set -e

MODE="${1:-quick}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[Scan]${NC} $1"; }
pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; }

ISSUES=0

echo ""
echo "========================================"
echo "  Security Scan ($MODE mode)"
echo "========================================"
echo ""

# 1. Secret detection with gitleaks
log "Checking for secrets..."
if command -v gitleaks &> /dev/null; then
    if gitleaks detect --no-banner --no-git -q 2>/dev/null; then
        pass "No secrets detected"
    else
        fail "Secrets detected! Run: gitleaks detect --verbose"
        ((ISSUES++))
    fi
else
    warn "gitleaks not installed"
fi

# 2. Python dependency vulnerabilities
if [ -f "requirements.txt" ] || [ -f "pyproject.toml" ]; then
    log "Checking Python dependencies..."
    if command -v safety &> /dev/null; then
        if safety check --output text 2>/dev/null | grep -q "No known security vulnerabilities"; then
            pass "No Python vulnerabilities found"
        else
            warn "Python vulnerabilities detected. Run: safety check"
            ((ISSUES++))
        fi
    elif command -v pip-audit &> /dev/null; then
        if pip-audit 2>/dev/null; then
            pass "No Python vulnerabilities found"
        else
            warn "Python vulnerabilities detected"
            ((ISSUES++))
        fi
    else
        warn "safety/pip-audit not installed"
    fi
fi

# 3. Python code security with bandit
if [ -f "pyproject.toml" ] || [ -d "src" ]; then
    log "Checking Python code security..."
    if command -v bandit &> /dev/null; then
        BANDIT_TARGET="."
        [ -d "src" ] && BANDIT_TARGET="src"
        if bandit -r "$BANDIT_TARGET" -q 2>/dev/null; then
            pass "No Python security issues"
        else
            warn "Python security issues found. Run: bandit -r $BANDIT_TARGET"
            ((ISSUES++))
        fi
    else
        warn "bandit not installed"
    fi
fi

# 4. Node dependency vulnerabilities
if [ -f "package.json" ]; then
    log "Checking Node dependencies..."
    if npm audit --audit-level=high 2>/dev/null; then
        pass "No high/critical Node vulnerabilities"
    else
        warn "Node vulnerabilities detected. Run: npm audit"
        ((ISSUES++))
    fi
fi

# 5. Container scanning (full mode only)
if [ "$MODE" = "full" ]; then
    if [ -f "Dockerfile" ] || [ -f "docker/Dockerfile" ]; then
        log "Scanning container image..."
        DOCKERFILE="Dockerfile"
        [ -f "docker/Dockerfile" ] && DOCKERFILE="docker/Dockerfile"

        if command -v trivy &> /dev/null; then
            # Scan the Dockerfile for misconfigurations
            if trivy config --severity HIGH,CRITICAL "$DOCKERFILE" 2>/dev/null; then
                pass "No Dockerfile issues"
            else
                warn "Dockerfile issues found"
                ((ISSUES++))
            fi
        else
            warn "trivy not installed"
        fi
    fi

    # Hadolint for Dockerfile best practices
    if [ -f "Dockerfile" ] && command -v hadolint &> /dev/null; then
        log "Linting Dockerfile..."
        if hadolint Dockerfile 2>/dev/null; then
            pass "Dockerfile follows best practices"
        else
            warn "Dockerfile improvements suggested"
        fi
    fi
fi

# Summary
echo ""
echo "========================================"
if [ $ISSUES -eq 0 ]; then
    pass "All checks passed!"
else
    fail "$ISSUES issue(s) found"
fi
echo "========================================"
echo ""

exit $ISSUES
