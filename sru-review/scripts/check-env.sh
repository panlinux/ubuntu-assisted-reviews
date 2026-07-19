#!/bin/bash
#
# check-env.sh
#
# Preflight check for the sru-review skill. Verify that every external tool the
# skill and its helper scripts rely on is installed and on $PATH, and print an
# install hint for anything missing. Run this once at the start of a review so
# the reviewer is alerted to missing tooling before the workflow begins,
# instead of discovering it midway through a check.
#
# Output: one line per required tool,
#     OK      <tool>
#     MISSING <tool>   (install: <hint>)
# followed by a final summary line.
#
# Exit status: 0 if every required tool is present, non-zero if any is missing.
set -uo pipefail

# tool -> human-readable install hint
tools=(
    "git-ubuntu:snap install git-ubuntu --classic"
    "ubuntu-distro-info:apt install distro-info"
    "dpkg-parsechangelog:apt install dpkg-dev"
    "jq:apt install jq"
    "curl:apt install curl"
    "lynx:apt install lynx"
)

missing=0
for entry in "${tools[@]}"; do
    tool=${entry%%:*}
    hint=${entry#*:}
    if command -v "$tool" >/dev/null 2>&1; then
        printf 'OK      %s\n' "$tool"
    else
        printf 'MISSING %s   (install: %s)\n' "$tool" "$hint"
        missing=$((missing + 1))
    fi
done

echo
if [ "$missing" -eq 0 ]; then
    echo "ENV=ok (all required tools present)"
    exit 0
fi

echo "ENV=missing (${missing} tool(s) missing -- install them before reviewing)"
exit 1
