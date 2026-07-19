#!/bin/bash
#
# gather-context.sh [checkout-dir]
#
# Run inside (or point at) a git-ubuntu checkout produced by:
#     git ubuntu clone <package> && cd <package> && git ubuntu queue sync
#
# Prints the core facts about the topmost upload that nearly every later check
# depends on, so the reviewer does not have to re-derive them:
#
#     SOURCE=<source package name>
#     VERSION=<full version of the top changelog stanza>
#     TARGET_SERIES=<distribution/series the upload targets, e.g. noble>
#     URGENCY=<urgency>
#     LP_BUGS=<space separated LP bug numbers referenced in the top stanza>
#     QUEUE_TAGS=<matching queue/<release>/unapproved/<hash> tags, if any>
#
# On failure (not a checkout, no changelog): exit non-zero with a message on
# stderr.
set -euo pipefail

die() { echo "gather-context: $*" >&2; exit 1; }

dir=${1:-.}
cd "$dir" || die "cannot cd into '$dir'"

[ -f debian/changelog ] || die "no debian/changelog found in '$dir' (is this a git-ubuntu checkout?)"

# Parse only the topmost (most recent) changelog stanza.
source=$(dpkg-parsechangelog -S Source)
version=$(dpkg-parsechangelog -S Version)
series=$(dpkg-parsechangelog -S Distribution)
urgency=$(dpkg-parsechangelog -S Urgency 2>/dev/null || echo "unknown")

# Referenced LP bugs: dpkg-parsechangelog exposes them via -S Closes for
# "LP: #NNNN" and "Closes: NNNN" style entries; fall back to scraping the raw
# top stanza for "LP: #NNNN" just in case.
bugs=$(dpkg-parsechangelog -S Closes 2>/dev/null | tr ' ' '\n' | grep -E '^[0-9]+$' || true)
if [ -z "$bugs" ]; then
    bugs=$(dpkg-parsechangelog -S Changes 2>/dev/null \
        | grep -oiE 'LP: *#[0-9]+' | grep -oE '[0-9]+' || true)
fi
bugs=$(printf '%s\n' $bugs | sort -un | xargs || true)

# Queue tags present in this checkout, if run inside a git repo.
qtags=""
if git rev-parse --git-dir >/dev/null 2>&1; then
    qtags=$(git tag -l 'queue/*/unapproved/*' | xargs || true)
fi

echo "SOURCE=${source}"
echo "VERSION=${version}"
echo "TARGET_SERIES=${series}"
echo "URGENCY=${urgency}"
echo "LP_BUGS=${bugs}"
echo "QUEUE_TAGS=${qtags}"
