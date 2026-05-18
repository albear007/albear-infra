# albear-infra — platform coordination commands (https://just.systems)
# Loads .env (gitignored) for deployment secrets. Copy .env.example to .env and fill in.

set dotenv-load

# Required env vars (defined in .env):
#   BOX_HOST           e.g. ubuntu@x.x.x.x
#   SSH_KEY            path to SSH key, e.g. ~/.ssh/oci_key
#   CERT_LOCAL_PATH    directory containing cert.pem and key.pem (for refresh-certs)

# All vars optional at parse time so local-only recipes (validate) don't
# require .env. Remote recipes assert the vars they need.
BOX_HOST := env_var_or_default('BOX_HOST', '')
SSH_KEY := env_var_or_default('SSH_KEY', '')
CERT_LOCAL_PATH := env_var_or_default('CERT_LOCAL_PATH', '')

# Internal: assert remote-deploy env vars are set
_check-remote-env:
    @test -n "{{BOX_HOST}}" || (echo "BOX_HOST not set — copy .env.example to .env and fill in" && exit 1)
    @test -n "{{SSH_KEY}}" || (echo "SSH_KEY not set — copy .env.example to .env and fill in" && exit 1)

# List available recipes
default:
    @just --list

# Uses `adapt`, not `validate`, so it doesn't try to load TLS certs that
# only exist on the box.
#
# Validate Caddyfile syntax locally
validate:
    @docker run --rm -v "$PWD/caddy:/caddy" caddy:alpine caddy adapt --config /caddy/Caddyfile.prod >/dev/null \
        && echo "Caddyfile.prod syntax OK"

# Full pre-deploy check. Run before `just deploy-gateway` or
# `just update-firewall` — catches the bad-config classes that have
# historically locked the operator out of production:
#   1. Caddyfile + every snippet parses (caddy adapt)
#   2. Every `import` in Caddyfile.prod resolves to a real file
#   3. firewall/allowed-ips is well-formed (every line is a valid IP/CIDR)
#   4. firewall/update-firewall.sh passes shellcheck
#   5. Update-firewall's --dry-run output matches the snapshot
#   6. The validators themselves reject known-bad input
test:
    bash tests/validate_caddy.sh
    python3 tests/validate_allowed_ips.py
    bash tests/validate_firewall_script.sh
    bash tests/dry_run_firewall.sh
    bash tests/test_validators.sh

# Restart (not reload) is required — reload silently no-ops in this
# environment. See docs/2026-04-30-foundation.md decision 7.
#
# Pull repo, rebuild Caddy stack, restart Caddy on the box
deploy-gateway: _check-remote-env
    ssh -i {{SSH_KEY}} {{BOX_HOST}} \
        "cd ~/infra && \
         git pull && \
         docker compose up -d && \
         docker compose restart caddy"

# allowed-ips is gitignored — the local file is the source of truth.
#
# Sync operator allowlist and rerun firewall script on the box
update-firewall: _check-remote-env
    @test -f firewall/allowed-ips || (echo "firewall/allowed-ips not found — create it (gitignored)" && exit 1)
    scp -i {{SSH_KEY}} firewall/allowed-ips {{BOX_HOST}}:~/infra/firewall/allowed-ips
    ssh -i {{SSH_KEY}} {{BOX_HOST}} 'bash ~/infra/firewall/update-firewall.sh'

# CERT_LOCAL_PATH must contain cert.pem and key.pem.
#
# Push fresh TLS cert + key and restart Caddy
refresh-certs: _check-remote-env
    @test -n "{{CERT_LOCAL_PATH}}" || (echo "CERT_LOCAL_PATH not set in .env" && exit 1)
    @test -f "{{CERT_LOCAL_PATH}}/cert.pem" || (echo "{{CERT_LOCAL_PATH}}/cert.pem not found" && exit 1)
    @test -f "{{CERT_LOCAL_PATH}}/key.pem" || (echo "{{CERT_LOCAL_PATH}}/key.pem not found" && exit 1)
    scp -i {{SSH_KEY}} "{{CERT_LOCAL_PATH}}/cert.pem" {{BOX_HOST}}:~/infra/certs/cert.pem
    scp -i {{SSH_KEY}} "{{CERT_LOCAL_PATH}}/key.pem" {{BOX_HOST}}:~/infra/certs/key.pem
    ssh -i {{SSH_KEY}} {{BOX_HOST}} 'cd ~/infra && docker compose restart caddy'

# The target arg matches JBAgent's docs (`just provision <target>`); the
# actual sequence is in runbooks/vm-migration-platform.md.
#
# Pointer to the provisioning runbook (interactive, can't be one-liner)
provision target='':
    @echo "Provisioning is too involved for a one-liner."
    @if [ -n "{{target}}" ]; then echo "Target: {{target}}"; fi
    @echo "See runbooks/vm-migration-platform.md for the full sequence."
    @echo "Pair with JBAgent/docs/2026-04-29-jbagent-app-bootstrap.md for the JBAgent half."

# Open a shell on the box
ssh: _check-remote-env
    ssh -i {{SSH_KEY}} {{BOX_HOST}}

# Tail Caddy logs from the box
logs: _check-remote-env
    ssh -i {{SSH_KEY}} {{BOX_HOST}} 'cd ~/infra && docker compose logs --tail=100 -f caddy'
