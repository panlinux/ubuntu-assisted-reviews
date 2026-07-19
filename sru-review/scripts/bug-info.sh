#!/bin/bash
#
# bug-info.sh <bug-number> [bug-number ...]
#
# Query the Launchpad API for each bug and print whether it is public and its
# per-series task status. This supports several report checks:
#   - check 2  (bugs publicly accessible): PRIVATE=false means public.
#   - check 16 (correct release tasks): the per-series task list shows whether
#     every target release has a task.
#   - checks 9/10 (fix in later/devel releases): a series task of "Fix
#     Released" corroborates that the fix has landed there. This is supporting
#     evidence only -- still compare the actual diff / rmadison-matrix.sh.
#
# Output per bug:
#     === BUG <n>: <title> ===
#     PRIVATE=<true|false>
#     TASK  <bug_target_name>  <status>
#     ...
#
# A bug that cannot be fetched publicly (HTTP error) is reported as
#     PRIVATE=unknown (not publicly reachable)
# which should be treated as a check-2 concern.
#
# Requires curl and jq.
set -euo pipefail

die() { echo "bug-info: $*" >&2; exit 1; }

[ $# -ge 1 ] || die "usage: bug-info.sh <bug-number> [bug-number ...]"
command -v jq >/dev/null 2>&1 || die "jq not found"

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
    if ! json=$(fetch "${api}/${bug}"); then
        echo "=== BUG ${bug}: <unreachable> ==="
        echo "PRIVATE=unknown (not publicly reachable -- check 2 concern)"
        echo
        rc=1
        continue
    fi

    title=$(printf '%s' "$json" | jq -r '.title // "<no title>"')
    private=$(printf '%s' "$json" | jq -r '.private // false')

    echo "=== BUG ${bug}: ${title} ==="
    echo "PRIVATE=${private}"

    if tasks=$(fetch "${api}/${bug}/bug_tasks"); then
        printf '%s' "$tasks" \
            | jq -r '.entries[] | "TASK\t\(.bug_target_name)\t\(.status)"' \
            | column -t -s $'\t'
    else
        echo "TASK  <could not fetch bug_tasks>"
        rc=1
    fi
    echo
done

exit $rc
