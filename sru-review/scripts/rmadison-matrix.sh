#!/bin/bash
#
# rmadison-matrix.sh <package>
#
# Build a per-release source-version matrix for <package>, restricted to the
# still-supported Ubuntu releases plus the development release, so the reviewer
# can confirm the fix is present in later supported releases (report check 9)
# and in the devel release including its -proposed pocket (report check 10).
#
# It queries `rmadison -a source` and intersects the result with
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
# On failure (rmadison missing/errors): exit non-zero with a message on stderr.
set -euo pipefail

die() { echo "rmadison-matrix: $*" >&2; exit 1; }

[ $# -ge 1 ] || die "usage: rmadison-matrix.sh <package>"
package=$1

command -v rmadison >/dev/null 2>&1 || die "rmadison not found (install the 'devscripts' package)"
command -v ubuntu-distro-info >/dev/null 2>&1 || die "ubuntu-distro-info not found (install the 'distro-info' package)"

supported=$(ubuntu-distro-info --supported)
devel=$(ubuntu-distro-info --devel)

# Build a lookup of releases we care about.
declare -A keep
for r in $supported; do keep[$r]=1; done
keep[$devel]=1

madison=$(rmadison -a source "$package") || die "rmadison failed for '$package'"

echo "# Supported releases: $(echo $supported | tr '\n' ' ')"
echo "# Devel release:      ${devel}"
echo "# Package:            ${package}"
echo

printf '%s\n' "$madison" | while IFS='|' read -r pkg version suite arch; do
    version=$(echo "$version" | xargs)
    suite=$(echo "$suite" | xargs)
    # suite is like "noble", "noble-updates", "noble-security", "noble-proposed"
    release=${suite%%-*}
    [ -n "${keep[$release]:-}" ] || continue
    marker=""
    [ "$release" = "$devel" ] && marker="   [DEVEL]"
    printf '%-24s %s%s\n' "$suite" "$version" "$marker"
done
