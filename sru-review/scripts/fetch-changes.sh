#!/bin/bash
#
# fetch-changes.sh <release> <package> [version]
#
# Locate a source upload in the Launchpad "unapproved" queue for <release> and
# download its .changes file. Prints the local path to the downloaded file and
# the Launchpad-Bugs-Fixed field, so the reviewer can confirm that the bugs
# referenced in debian/changelog also appear in the .changes file (report
# check 3).
#
# If [version] is given, only the upload matching that exact version is
# selected; otherwise every matching source upload found in the queue is
# reported (there is normally only one).
#
# On success: exit 0, having printed one or more blocks of the form
#     CHANGES_FILE=<local path>
#     CHANGES_URL=<launchpad url>
#     VERSION=<version>
#     LAUNCHPAD_BUGS_FIXED=<space separated bug numbers, or empty>
#
# On failure (upload not found, network error): exit non-zero with a message on
# stderr. Fall back to browsing the queue manually at
#     https://launchpad.net/ubuntu/<release>/+queue?queue_state=1
set -euo pipefail

die() { echo "fetch-changes: $*" >&2; exit 1; }

[ $# -ge 2 ] || die "usage: fetch-changes.sh <release> <package> [version]"
release=$1
package=$2
want_version=${3:-}
# .changes filenames carry the epoch-stripped version (e.g. "28.0.0-0ubuntu1.1",
# never "2:28.0.0-0ubuntu1.1"), so drop a leading "<epoch>:" from the requested
# version before matching. This lets callers pass the version verbatim from
# gather-context.sh / dpkg-parsechangelog, which includes the epoch.
want_version=${want_version#*:}

queue_url="https://launchpad.net/ubuntu/${release}/+queue?queue_state=1&queue_text=${package}"

# Retry transient 5xx errors up to 3 times.
fetch() {
    local url=$1 out=${2:-} attempt
    for attempt in 1 2 3; do
        if [ -n "$out" ]; then
            if curl -sL --fail -o "$out" "$url"; then return 0; fi
        else
            if curl -sL --fail "$url"; then return 0; fi
        fi
        sleep 2
    done
    return 1
}

page=$(fetch "$queue_url") || die "could not fetch queue page: $queue_url"

# Extract all *_source.changes URLs for this release's upload queue.
mapfile -t urls < <(printf '%s' "$page" \
    | grep -oE "https://launchpad.net/ubuntu/${release}/\\+upload/[0-9]+/\\+files/[^\"']*_source\\.changes" \
    | sort -u)

[ ${#urls[@]} -gt 0 ] || die "no source .changes upload found for '${package}' in ${release} unapproved queue"

tmpdir=$(mktemp -d)
found=0
for url in "${urls[@]}"; do
    fname=${url##*/}
    # Filenames look like: <src>_<version>_source.changes
    base=${fname%_source.changes}
    version=${base#*_}

    if [ -n "$want_version" ] && [ "$version" != "$want_version" ]; then
        continue
    fi

    out="${tmpdir}/${fname}"
    fetch "$url" "$out" || die "failed to download changes file: $url"

    bugs=$(grep -iE '^Launchpad-Bugs-Fixed:' "$out" | head -1 | cut -d: -f2- | xargs || true)

    echo "CHANGES_FILE=${out}"
    echo "CHANGES_URL=${url}"
    echo "VERSION=${version}"
    echo "LAUNCHPAD_BUGS_FIXED=${bugs}"
    echo
    found=1
done

[ "$found" -eq 1 ] || die "no upload matching version '${want_version}' found for '${package}' in ${release}"
