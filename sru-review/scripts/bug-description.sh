#!/bin/bash
#
# bug-description.sh <bug-number> [bug-number ...]
#
# Print the full text description of each Launchpad bug via the Launchpad API.
# This is the SRU template ([Impact], [Test Plan], [Where problems could
# occur], [Regression potential], ...) and supports report checks 17, 19 and
# 20 without scraping the bug's HTML page (whose <meta description> is
# truncated).
#
# Output per bug:
#     === BUG <n> DESCRIPTION ===
#     <full description text>
#     === END BUG <n> ===
#
# On a bug that cannot be fetched publicly, prints an <unreachable> marker and
# contributes a non-zero exit (a check-2 concern).
#
# Requires curl and jq.
set -euo pipefail

die() { echo "bug-description: $*" >&2; exit 1; }

[ $# -ge 1 ] || die "usage: bug-description.sh <bug-number> [bug-number ...]"
command -v jq >/dev/null 2>&1 || die "jq not found"
command -v curl >/dev/null 2>&1 || die "curl not found"

api="https://api.launchpad.net/devel/bugs"

fetch() {
    local url=$1 attempt
    for attempt in 1 2 3; do
        if curl -sL --fail "$url"; then return 0; fi
        sleep 2
    done
    return 1
}

rc=0
for bug in "$@"; do
    bug=${bug#\#}
    echo "=== BUG ${bug} DESCRIPTION ==="
    if json=$(fetch "${api}/${bug}"); then
        printf '%s\n' "$json" | jq -r '.description // "<no description>"'
    else
        echo "<unreachable -- not publicly reachable (check 2 concern)>"
        rc=1
    fi
    echo "=== END BUG ${bug} ==="
    echo
done

exit $rc
