#!/bin/bash
#
# phasing-status.sh <package> [url]
#
# Determine whether <package> currently appears on
# https://phased-updates.ubuntu.com/ and, if so, whether its phased update has
# been halted (update percentage 0%). This supports report check 21.
#
# An optional [url] overrides the page fetched (default:
# https://phased-updates.ubuntu.com/). Use it to point at the equivalent
# https://ubuntu-archive-team.ubuntu.com/phased-updates.html or a Wayback
# Machine snapshot for testing/historical review.
#
# The page lists a package/release row while an SRU is being phased. A non-zero
# percentage means phasing is progressing normally; 0% means phasing has been
# stopped, typically because of an increased crash rate or an error seen only
# with the SRU'ed version -- in that case the reviewer must confirm the upload
# under review addresses the failure.
#
# Output:
#     PHASING=<none|ok|halted>
#     # none   -> package not listed; check 21 is N/A
#     # ok     -> listed and still phasing (non-zero %); no halt to address
#     # halted -> listed at 0%; verify this upload fixes the regression
# followed, when the package is listed, by the matching context rows so the
# reviewer can inspect versions/releases/percentages directly.
#
# On network failure (after retries): exit non-zero with a message on stderr.
# Requires curl and lynx.
set -euo pipefail

die() { echo "phasing-status: $*" >&2; exit 1; }

[ $# -ge 1 ] || die "usage: phasing-status.sh <package> [url]"
package=$1
command -v curl >/dev/null 2>&1 || die "curl not found"
command -v lynx >/dev/null 2>&1 || die "lynx not found (install the 'lynx' package)"

url=${2:-"https://phased-updates.ubuntu.com/"}

fetch() {
    local u=$1 attempt
    for attempt in 1 2 3; do
        if curl -sL --fail "$u"; then return 0; fi
        sleep 2
    done
    return 1
}

page=$(fetch "$url") || die "could not fetch phasing page: $url"

# Render the HTML table to text with lynx: each package row becomes a single
# line (a wide -width avoids wrapping long rows), which is far more robust than
# stripping tags by hand. Keep only rows mentioning the package as a whole word.
rows=$(printf '%s' "$page" \
    | lynx -dump -nolist -width=1000 -stdin 2>/dev/null \
    | grep -wE "$package" \
    | sed -e 's/^ *//' -e 's/ *$//' -e 's/  */ /g' \
    || true)

if [ -z "$rows" ]; then
    echo "PHASING=none"
    exit 0
fi

# A halted update shows an update percentage of 0% (0, 0.0, 0% ...).
if printf '%s\n' "$rows" | grep -qE '(^| )0(\.0+)? *%'; then
    echo "PHASING=halted"
else
    echo "PHASING=ok"
fi

echo "# matching rows:"
printf '%s\n' "$rows" | sed 's/^/#   /'
