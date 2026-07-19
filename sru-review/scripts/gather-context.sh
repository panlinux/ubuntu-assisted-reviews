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
#     QUEUE_TAGS=<queue/<release>/unapproved/<hash> tag pointing at HEAD>
#     BASELINE_REF=<git ref to diff the queue tag against, if resolvable>
#
# BASELINE_REF is the release baseline the upload should be compared against
# (normally pkg/ubuntu/<series>-devel). It is emitted only when it resolves to
# a real object in this repo, so Stage B can diff reliably:
#     git diff "$BASELINE_REF" "$QUEUE_TAGS"
#
# On failure (not a checkout, no changelog, or HEAD does not identify exactly
# one queue tag): exit non-zero with a message on stderr.
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

# Extract only explicit Launchpad references from the top stanza. The
# dpkg-parsechangelog Closes field is for Debian bugs and must not satisfy the
# SRU requirement for an LP bug.
bugs=$(dpkg-parsechangelog -S Changes 2>/dev/null \
    | grep -oiE 'LP: *#[0-9]+( *, *#[0-9]+)*' \
    | grep -oE '[0-9]+' || true)
bugs=$(printf '%s\n' $bugs | sort -un | xargs || true)

# Identify the single queue upload checked out at HEAD.
qtags=""
baseline=""
if git rev-parse --git-dir >/dev/null 2>&1; then
    mapfile -t head_qtags < <(git tag --points-at HEAD -l 'queue/*/unapproved/*')
    case ${#head_qtags[@]} in
        0) die "HEAD is not tagged as queue/<release>/unapproved/<hash>" ;;
        1) qtags=${head_qtags[0]} ;;
        *) die "HEAD has multiple unapproved queue tags: ${head_qtags[*]}" ;;
    esac

    # Resolve the release baseline to diff the upload against. Try the
    # conventional git-ubuntu refs in order and keep the first that exists as a
    # real object (tag, remote-tracking branch, ...).
    for cand in \
        "pkg/ubuntu/${series}-devel" \
        "refs/tags/pkg/ubuntu/${series}-devel" \
        "remotes/pkg/ubuntu/${series}-devel" \
        "pkg/ubuntu/${series}"; do
        if git rev-parse --verify --quiet "${cand}^{commit}" >/dev/null 2>&1; then
            baseline=$cand
            break
        fi
    done
fi

echo "SOURCE=${source}"
echo "VERSION=${version}"
echo "TARGET_SERIES=${series}"
echo "URGENCY=${urgency}"
echo "LP_BUGS=${bugs}"
echo "QUEUE_TAGS=${qtags}"
echo "BASELINE_REF=${baseline}"
