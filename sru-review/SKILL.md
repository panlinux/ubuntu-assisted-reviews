---
name: sru-review
description: Review an Ubuntu Stable Release Update (SRU) from a git-ubuntu tag of the form queue/<release>/unapproved/<hash> and produce a report with a recommendation.
---

## Persona

You are an experienced Ubuntu packager and SRU reviewer. Verify that the upload meets Ubuntu SRU standards for stable releases.

## Prerequisites

- `git-ubuntu` must be available (install via snap if missing).
- `distro-info` must be available to determine which Ubuntu releases are still supported (install via the `distro-info` package).
- `jq` and `curl` must be available (used by the helper scripts).
- `lynx` must be available (used by `phasing-status.sh` to render the phased
  updates table to text).

Run `"$SRU_SCRIPTS/check-env.sh"` (see **Helper scripts** below for
`$SRU_SCRIPTS`) at the start of a review to confirm all of the above are
installed; it prints an install hint for anything missing and exits non-zero
if the environment is incomplete.

### Helper scripts

This skill ships helper scripts in the `scripts/` directory next to this file
that do the mechanical, error-prone parts of the review the same way every time.
**Prefer the scripts over reconstructing the commands yourself.** Set a variable
to the skill's `scripts/` directory once and invoke every helper through it:

```bash
SRU_SCRIPTS="<base directory of this skill>/scripts"
"$SRU_SCRIPTS/gather-context.sh"
```

Each script prints `KEY=value` lines or a small table for later steps. On
failure it writes to stderr and exits non-zero — fall back to the manual steps
alongside the affected check.

| Script | Purpose | Feeds checks |
|--------|---------|--------------|
| `check-env.sh` | Preflight: verify every required external tool is installed; print install hints for missing ones | (prerequisites) |
| `gather-context.sh [dir]` | Print source, version, target series, referenced LP bugs, queue tags, and the diff `BASELINE_REF` from the checkout | 1, 3, 4, 7 |
| `fetch-changes.sh <release> <package> [version]` | Download the `.changes` file from the unapproved queue and print its `Launchpad-Bugs-Fixed` | 3 |
| `rmadison-matrix.sh <package>` | Per-release version matrix limited to supported + devel releases (header also prints the supported/devel list) | 9, 10 |
| `bug-info.sh <bug> [<bug>...]` | Launchpad API: public flag + per-series task status for each bug | 2, 16 (corroborates 9, 10) |
| `bug-description.sh <bug> [<bug>...]` | Launchpad API: full bug description / SRU template text (avoids scraping truncated bug HTML) | 17, 19, 20 |
| `phasing-status.sh <package>` | Classify phased-updates.ubuntu.com status as `none`/`ok`/`halted` for the package | 21 |

**Batch the independent data-gathering scripts.** Once
`SOURCE`/`VERSION`/`TARGET_SERIES`/`LP_BUGS` are known from
`gather-context.sh`, the remaining scripts (`fetch-changes.sh`,
`rmadison-matrix.sh`, `bug-info.sh`, `bug-description.sh`,
`phasing-status.sh`) have no data dependencies on each other — run them in a
single batched turn.

## Fetching web resources

Several URLs encountered during review redirect across domains (e.g. `launchpad.net` → `launchpadlibrarian.net`, `ubuntu-archive-team.ubuntu.com` → `phased-updates.ubuntu.com`). The `web_fetch` tool refuses cross-domain redirects, so always use **`curl -sL`** instead for any URL on these domains:

- `launchpad.net` / `launchpadlibrarian.net`
- `ubuntu.com` / `ubuntu-archive-team.ubuntu.com` / `phased-updates.ubuntu.com`
- `canonical.com`

```bash
curl -sL "<url>"
```

If you receive an HTTP 5xx error, **retry up to 3 times** before treating it as a failure. (The helper scripts already retry internally.)

---

## Workflow

The workflow is grouped by **data source** so you gather each kind of evidence
once: set up and collect shared facts, then the local-checkout checks, then
archive checks, then Launchpad bug/test checks, then phasing, then the report.
Each step lists the report **check number(s)** it satisfies; the report
numbering is stable — only the order of work differs.

### Stage A — Setup & context

#### A0. Preflight: check the environment

Confirm every external tool the skill relies on is installed before starting.

```bash
"$SRU_SCRIPTS/check-env.sh"
```

If it reports any `MISSING` tool (exit non-zero), install the missing packages
using the printed hints — or alert the user — before continuing.

#### A1. Determine supported Ubuntu releases

Establish which releases are still supported (and which is the development
release). EOL releases are irrelevant to an SRU and should be ignored.

```bash
ubuntu-distro-info --supported   # supported releases, includes devel
ubuntu-distro-info --devel       # the current development release
```

This list scopes the cross-release checks in Stage C. If you are running
`rmadison-matrix.sh` (Stage C) anyway, its header already prints the supported
and devel releases, so you can read them from there instead.

#### A2. Fetch the upload

The goal of this step is a git-ubuntu checkout that contains tags of the form
`queue/<release>/unapproved/<hash>`. Both commands below are conditional — skip
whichever the current directory already satisfies.

**Clone** — only if you are not already inside a checkout. If the current
directory is already a git-ubuntu checkout of the target package (it has a
`debian/changelog` for that source and a `.git` directory), skip this and work
in place:

```bash
git ubuntu clone <source-package>
cd <source-package>
```

**Queue sync** — only if the checkout does not already contain a queue tag.
Check first, and run the sync only when the list is empty:

```bash
git tag -l 'queue/*/unapproved/*'   # if this prints nothing, sync:
git ubuntu queue sync
```

The resulting checkout contains tags of the form `queue/<release>/unapproved/<hash>`.

**Check out the queue tag** before any other analysis and stay on it for the
whole review.

```bash
git tag -l 'queue/*/unapproved/*'                 # pick the target tag
git checkout queue/<release>/unapproved/<hash>     # detached HEAD is expected
dpkg-parsechangelog -S Distribution                # sanity check: NOT unstable/UNRELEASED
```

#### A3. Gather context

From inside the checkout (with the queue tag checked out, per A2):

```bash
"$SRU_SCRIPTS/gather-context.sh"
```

Record the printed `SOURCE`, `VERSION`, `TARGET_SERIES`, `LP_BUGS`,
`QUEUE_TAGS` (the single queue tag pointing at `HEAD`), and `BASELINE_REF` (the
ref Stage B diffs against, normally `pkg/ubuntu/<series>-devel`; emitted only
when it resolves in the checkout). These feed nearly every later check.
**Expected outcome:** a single top changelog stanza referencing at least one
`LP: #NNNN` bug.
- **Check 1 (bug references in changelog):** PASS if `LP_BUGS` is non-empty;
  FAIL if the topmost stanza references no Launchpad bug.

Then kick off the independent data-gathering scripts (A4 and Stages C/D/E) in a
single batched turn — see **Batch the independent data-gathering scripts**
above.

#### A4. Fetch the `.changes` file

```bash
"$SRU_SCRIPTS/fetch-changes.sh" "<TARGET_SERIES>" "<SOURCE>" "<VERSION>"
```

Record `CHANGES_FILE` and `LAUNCHPAD_BUGS_FIXED`.
- **Check 3 (bug references in `source.changes`):** PASS if the bug numbers in
  `LAUNCHPAD_BUGS_FIXED` match `LP_BUGS` from A3; FAIL if they differ or the
  `.changes` omits a bug the changelog closes. N/A only if the upload
  legitimately closes no bug. If the script cannot find the upload, check
  `https://launchpad.net/ubuntu/<release>/+queue?queue_state=1` before deciding.

### Stage B — Local checkout / diff checks

Inspect the upload diff (`git ubuntu` checkout). Diff the queue tag against the
`BASELINE_REF` emitted by `gather-context.sh` (normally
`pkg/ubuntu/<TARGET_SERIES>-devel`):

```bash
git --no-pager diff "$BASELINE_REF" "$QUEUE_TAGS"
```

If `BASELINE_REF` is empty, the conventional ref did not resolve — verify it
(e.g. `git rev-parse --verify pkg/ubuntu/<TARGET_SERIES>-devel`) before diffing.
All of these checks are answered from the checkout alone.

#### B1. Changes quality
- **Check 4 (minimal change):** PASS if the diff is minimal and focused on the
  reported bug(s); FAIL if it contains substantial unrelated work.
- **Check 5 (no unrelated changes):** PASS if every hunk maps to a bug fix
  named in the changelog; FAIL if unrelated files/lines are touched. Expected
  Ubuntu packaging deltas (e.g. the `Maintainer`/`XSBC-Original-Maintainer`
  update from `update-maintainer`, Check 14) are fine and need not be listed in
  the changelog.
- **Check 6 (DEP-3 patch format):** For every *new* file under `debian/patches/`,
  PASS if it carries DEP-3 headers (`Description`, `Origin`/`Author`, `Bug`,
  etc.); FAIL if a new patch lacks them. N/A if no new patches are added.
- **Check 7 (correct versioning):** PASS if `VERSION` follows SRU convention
  (`<oldversion>+esm*`, or `<release-number>.<n>` style appropriate to the
  target series); FAIL otherwise.

#### B2. Packaging specifics
- **Check 13 (NEW packages in control):** Inspect `debian/control`. PASS if the
  set of binary packages is unchanged; FAIL (blocking) if any binary package is
  **new** — this requires an AA/SRU combined review per
  [non-standard SRU processes](https://documentation.ubuntu.com/sru/en/latest/explanation/non-standard-processes/#new-queue-in-the-sru-context).
- **Check 14 (maintainer has ubuntu.com email):** PASS if the `Maintainer:`
  field in `debian/control` uses an `ubuntu.com` address (i.e.
  `update-maintainer` was run); FAIL otherwise.
- **Check 15 (no translation changes):** PASS if the diff does not alter
  translation templates/`.po` files; FAIL if translations are affected.

#### B3. New upstream / uscan
- **Check 11 (new upstream / uscan):** If the upload introduces a new upstream
  version, run `uscan` and confirm the tarball is verifiable. PASS if `uscan`
  works and the orig tarball matches; FAIL if not. N/A if no new upstream
  version is included.

### Stage C — Archive / cross-release checks

Confirm the fix has landed everywhere it must. Build the version matrix once:

```bash
"$SRU_SCRIPTS/rmadison-matrix.sh" "<SOURCE>"
```

For each relevant release, confirm the same fix (or an equivalent/superseding
fix) is present, comparing against the release's changelog/diff
(`pkg/ubuntu/<release>-devel`). A `Fix Released` series task from `bug-info.sh`
is strong corroborating evidence. Treat `rmadison-matrix.sh` versions as
**authoritative**: if a `pkg/ubuntu/<release>-devel` branch shows an older
version than the matrix, the branch is stale — trust rmadison and confirm
against the archive source (`pull-lp-source <SOURCE> <release>`).

- **Check 8 (no co-dependent SRU):** PASS if this upload does not require
  another SRU to land simultaneously; FAIL if it depends on an unlanded SRU.
- **Check 9 (fix in later releases):** PASS if the fix is present in **every
  later supported release** shown in the matrix; FAIL if any later supported
  release lacks it.
- **Check 10 (fix in devel release):** PASS if the fix is in the current devel
  release. If present only in the devel `-proposed` pocket (matrix rows marked
  `[DEVEL]` under `<devel>-proposed`), mark **⚠️ PASS (devel-proposed)** and note
  the pending migration in Details. FAIL if the devel release lacks it entirely.

### Stage D — Launchpad bug / test-plan checks

Query every referenced bug once for its status and tasks, and fetch its full
description (SRU template) via the Launchpad API in the same batch:

```bash
"$SRU_SCRIPTS/bug-info.sh" <LP_BUGS>
"$SRU_SCRIPTS/bug-description.sh" <LP_BUGS>
```

Use `bug-description.sh` output for the template/test-plan checks below — it
returns the complete `[Impact]` / `[Test Plan]` / `[Where problems could occur]`
text from the API. (You may still open the bug via `curl -sL` to read reviewer
comments or attachments not in the description.)

- **Check 2 (bugs publicly accessible):** PASS if `bug-info.sh` reports
  `PRIVATE=false` for every bug; FAIL if any bug is private or unreachable.
- **Check 16 (correct release tasks):** PASS if each bug has an Ubuntu series
  task for **every target release** of this SRU (visible in the `TASK` rows);
  FAIL if a target release task is missing.
- **Check 17 (SRU template filled):** Read the description of each bug from
  `bug-description.sh`. PASS if the SRU template ([Impact], [Test Plan], [Where
  problems could occur], [Regression potential]) is completely and correctly
  filled in and not blocked by an unanswered reviewer question; FAIL if
  incomplete or unresolved.
- **Check 18 (kernel GA & HWE in plan):** If the package is a **kernel**, PASS
  only if both GA and HWE kernels are covered by the test plan; FAIL otherwise.
  N/A for non-kernel packages.
- **Check 19 (test plan covers usage):** PASS if the test plan exercises
  **normal usage** of the package (not merely the specific code change, e.g. not
  only a symbol-presence check); FAIL if it only verifies the narrow change.
- **Check 20 (good user story in plan):** PASS if the test plan tells a
  coherent, reproducible user story an admin could follow to confirm the fix;
  FAIL if it does not.
- **Check 12 (package-specific procedure):** If a bug claims a package-specific
  procedure, consult
  [package-specific SRU instructions](https://documentation.ubuntu.com/sru/en/latest/reference/package-specific/).
  PASS if the procedure was followed; FAIL if not. N/A if no such procedure
  applies.

### Stage E — Archive automation

- **Check 21 (phasing errors addressed):** Run `"$SRU_SCRIPTS/phasing-status.sh"
  <SOURCE>`. `PHASING=none` → not phasing, **N/A**. `PHASING=ok` → phasing
  normally, **N/A** (note it is in progress). `PHASING=halted` → phasing stopped
  (0%): inspect the matching rows and PASS only if this upload addresses the
  failure; FAIL if the regression is unaddressed.

### Stage F — Finalize

Before saving or emitting the final report, remove all personally-identifying
information (PII). Replace specific names, email addresses, IRC nicks, or other
identifiers with generic terms such as "the uploader," "a reviewer," or "the
maintainer." Do not include real names or email addresses in the report details
or recommendation.

---

## Report template

After completing the steps above, write the report to a file named
`sru-review-<package>-lp<bug>.md` (use the primary bug number from the
changelog) and emit it as a **Markdown** document.

The report skeleton lives in [`report-template.md`](report-template.md) next to
this file. Read it once you reach this stage and fill it in: replace the
`<...>` placeholders, set each check to `✅ PASS` / `❌ FAIL` / `— N/A`, and
follow the HTML-comment instructions in the Details and Recommendation
sections. The `Agent`, `Model`, and `Model version` header fields are
mandatory: identify the agent/CLI tool and the exact model (name and version)
used to generate the report, so the review's provenance is recorded. The check
numbers in the template are stable and map to the Stage steps above.

Load the template like any other helper artifact:

```bash
cat "$SRU_SCRIPTS/../report-template.md"
```

Stop after emitting the report.
