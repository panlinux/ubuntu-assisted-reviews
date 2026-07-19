#!/bin/bash
#
# rmadison-matrix.sh <package>
#
# Build a per-release source-version matrix for <package>, restricted to the
# still-supported Ubuntu releases plus the development release, so the reviewer
# can confirm the fix is present in later supported releases (report check 9)
# and in the devel release including its -proposed pocket (report check 10).
#
# It queries the Launchpad API's archive.getPublishedSources() operation for
# the primary archive and intersects the result with
# `ubuntu-distro-info --supported` / `--devel`, dropping EOL releases that are
# irrelevant to an SRU review.
#
# Output (one line per release/pocket that carries the package):
#     <release>-<pocket>  <version>   [DEVEL]
# where DEVEL marks rows belonging to the current development release.
#
# The reviewer still has to compare the *content* of each release against this
# SRU (or trust the Launchpad bug tasks via bug-info.sh); this script only
# tells you which versions are where.
#
# On failure (API/network error): exit non-zero with a message on stderr.
set -euo pipefail

die() { echo "rmadison-matrix: $*" >&2; exit 1; }

[ $# -ge 1 ] || die "usage: rmadison-matrix.sh <package>"
package=$1

command -v jq >/dev/null 2>&1 || die "jq not found"
command -v ubuntu-distro-info >/dev/null 2>&1 || die "ubuntu-distro-info not found (install the 'distro-info' package)"

supported=$(ubuntu-distro-info --supported)
devel=$(ubuntu-distro-info --devel)

# Build a lookup of releases we care about.
declare -A keep
for r in $supported; do keep[$r]=1; done
keep[$devel]=1

# Retry transient 5xx errors up to 3 times.
fetch() {
    local url=$1 attempt
    for attempt in 1 2 3; do
        if curl -sL --fail "$url"; then return 0; fi
        sleep 2
    done
    return 1
}

api_url="https://api.launchpad.net/devel/ubuntu/+archive/primary?ws.op=getPublishedSources&source_name=${package}&exact_match=true&status=Published"

json=$(fetch "$api_url") || die "could not query Launchpad API for '$package'"

echo "# Supported releases: $(echo $supported | tr '\n' ' ')"
echo "# Devel release:      ${devel}"
echo "# Package:            ${package}"
echo

printf '%s\n' "$json" \
    | jq -r '.entries[] | [(.distro_series_link | split("/") | last), .pocket, .source_package_version] | @tsv' \
    | while IFS=$'\t' read -r release pocket version; do
        [ -n "${keep[$release]:-}" ] || continue
        # Pocket names from the API ("Release", "Updates", "Security",
        # "Proposed", "Backports") map to rmadison-style suite suffixes.
        if [ "$pocket" = "Release" ]; then
            suite="$release"
        else
            suite="${release}-$(echo "$pocket" | tr '[:upper:]' '[:lower:]')"
        fi
        marker=""
        [ "$release" = "$devel" ] && marker="   [DEVEL]"
        printf '%-24s %s%s\n' "$suite" "$version" "$marker"
    done | sort -k1,1
