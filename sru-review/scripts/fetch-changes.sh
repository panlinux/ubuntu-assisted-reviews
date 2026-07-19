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
# Uses the Launchpad API's distro_series.getPackageUploads() operation
# (exact_match=true, status=Unapproved) to look up the upload.
#
# If [version] is given, only the upload matching that exact version (as
# returned by the API, including any epoch) is selected; otherwise every
# matching source upload found in the queue is reported (there is normally
# only one).
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
command -v jq >/dev/null 2>&1 || die "jq not found"
release=$1
package=$2
want_version=${3:-}

api_url="https://api.launchpad.net/devel/ubuntu/${release}?ws.op=getPackageUploads&status=Unapproved&name=${package}&exact_match=true"

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

json=$(fetch "$api_url") || die "could not query Launchpad API: $api_url"

# Only source uploads have a .changes file; contains_source filters out
# binary-only/copy entries.
mapfile -t rows < <(printf '%s' "$json" \
    | jq -r '.entries[] | select(.contains_source) | [.package_version, .changes_file_url] | @tsv')

[ ${#rows[@]} -gt 0 ] || die "no source .changes upload found for '${package}' in ${release} unapproved queue"

tmpdir=$(mktemp -d)
found=0
for row in "${rows[@]}"; do
    IFS=$'\t' read -r version url <<<"$row"

    if [ -n "$want_version" ] && [ "$version" != "$want_version" ]; then
        continue
    fi

    fname=${url##*/}
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
