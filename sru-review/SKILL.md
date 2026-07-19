---
name: sru-review
description: Review an Ubuntu Stable Release Update (SRU) from a git-ubuntu tag of the form queue/<release>/unapproved/<hash> and produce a report with a recommendation.
---

## Persona

You are an experienced Ubuntu packager and SRU reviewer. Verify that the upload meets Ubuntu SRU standards for stable releases.

## Prerequisites

- `git-ubuntu` must be available (install via snap if missing).
- `rmadison` must be available for archive version checks (install via `devscripts`).
- `distro-info` must be available to determine which Ubuntu releases are still supported (install via the `distro-info` package).
- `jq` and `curl` must be available (used by the helper scripts).

### Helper scripts

This skill ships helper scripts in the `scripts/` directory next to this file.
They exist to do the mechanical, error-prone parts of the review the same way
every time. **Prefer the script over reconstructing the commands yourself.** Run
each script with no arguments (or the wrong ones) to see its usage. Every script
prints `KEY=value` lines or a small table that later steps consume. If a script
fails, it prints a message on stderr and exits non-zero — fall back to the
manual steps documented alongside each check.

| Script | Purpose | Feeds checks |
|--------|---------|--------------|
| `gather-context.sh [dir]` | Print source, version, target series, referenced LP bugs, and queue tags from the checkout | 1, 3, 4, 7 |
| `fetch-changes.sh <release> <package> [version]` | Download the `.changes` file from the unapproved queue and print its `Launchpad-Bugs-Fixed` | 3 |
| `rmadison-matrix.sh <package>` | Per-release version matrix limited to supported + devel releases | 9, 10 |
| `bug-info.sh <bug> [<bug>...]` | Launchpad API: public flag + per-series task status for each bug | 2, 16 (corroborates 9, 10) |

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
once: first set up and collect the shared facts, then run the checks that only
need the local checkout, then the archive checks, then the Launchpad bug/test
checks, then phasing, and finally emit the report. Each step lists the report
**check number(s)** it satisfies; the numbering in the report template never
changes, only the order in which you perform the work.

### Stage A — Setup & context

#### A1. Determine supported Ubuntu releases

Establish which releases are still supported (and which is the development
release). EOL releases are irrelevant to an SRU and should be ignored.

```bash
ubuntu-distro-info --supported   # supported releases, includes devel
ubuntu-distro-info --devel       # the current development release
```

This list scopes the cross-release checks in Stage C.

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

#### A3. Gather context

From inside the checkout:

```bash
scripts/gather-context.sh
```

Record the printed `SOURCE`, `VERSION`, `TARGET_SERIES`, `LP_BUGS`, and
`QUEUE_TAGS`. These feed nearly every later check. **Expected outcome:** a
single top changelog stanza that references at least one `LP: #NNNN` bug.
- **Check 1 (bug references in changelog):** PASS if `LP_BUGS` is non-empty;
  FAIL if the topmost stanza references no Launchpad bug.

#### A4. Fetch the `.changes` file

```bash
scripts/fetch-changes.sh "<TARGET_SERIES>" "<SOURCE>" "<VERSION>"
```

Record `CHANGES_FILE` and `LAUNCHPAD_BUGS_FIXED`.
- **Check 3 (bug references in `source.changes`):** PASS if the bug numbers in
  `LAUNCHPAD_BUGS_FIXED` match the `LP_BUGS` from A3; FAIL if they differ or the
  `.changes` file omits a bug the changelog closes. Mark **N/A only** if the
  upload legitimately closes no bug. Do **not** default this to N/A because the
  file was hard to find — the script fetches it. If the script cannot find the
  upload, browse `https://launchpad.net/ubuntu/<release>/+queue?queue_state=1`
  manually before deciding.

### Stage B — Local checkout / diff checks

Inspect the upload diff (`git ubuntu` checkout; compare the queue tag against
the release tag `pkg/ubuntu/<TARGET_SERIES>-devel`). All of these are answered
from the checkout alone.

#### B1. Changes quality
- **Check 4 (minimal change):** PASS if the diff is minimal and focused on the
  reported bug(s); FAIL if it contains substantial unrelated work.
- **Check 5 (no unrelated changes):** PASS if every hunk maps to a bug fix
  named in the changelog; FAIL if unrelated files/lines are touched.
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
scripts/rmadison-matrix.sh "<SOURCE>"
```

For each relevant release, compare its changelog/diff against this SRU (tag
`pkg/ubuntu/<release>-devel`) to confirm the same fix (or an equivalent /
superseding fix) is present. You may **corroborate** presence with the
Launchpad bug tasks from `bug-info.sh` (a `Fix Released` series task is strong
evidence), but still confirm against the actual change where practical.

- **Check 8 (no co-dependent SRU):** PASS if this upload does not require
  another SRU to land simultaneously; FAIL if it depends on an unlanded SRU.
- **Check 9 (fix in later releases):** PASS if the fix is present in **every
  later supported release** shown in the matrix; FAIL if any later supported
  release lacks it.
- **Check 10 (fix in devel release):** PASS if the fix is in the current devel
  release. If it is present only in the devel `-proposed` pocket (matrix rows
  marked `[DEVEL]` under `<devel>-proposed`) and has not yet migrated to the
  release pocket, mark **⚠️ PASS (devel-proposed)** and note the pending
  migration in the report Details. FAIL if the devel release lacks the fix
  entirely.

### Stage D — Launchpad bug / test-plan checks

Query every referenced bug once:

```bash
scripts/bug-info.sh <LP_BUGS>
```

Then read each bug's SRU template and test plan in the browser via `curl -sL`.

- **Check 2 (bugs publicly accessible):** PASS if `bug-info.sh` reports
  `PRIVATE=false` for every bug; FAIL if any bug is private or unreachable.
- **Check 16 (correct release tasks):** PASS if each bug has an Ubuntu series
  task for **every target release** of this SRU (visible in the `TASK` rows);
  FAIL if a target release task is missing.
- **Check 17 (SRU template filled):** Read the description of each bug. PASS if
  the SRU template ([Impact], [Test Plan], [Where problems could occur],
  [Regression potential]) is completely and correctly filled in and not blocked
  by an unanswered reviewer question; FAIL if incomplete or unresolved.
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

- **Check 21 (phasing errors addressed):** Visit
  <https://phased-updates.ubuntu.com/>. If phasing of this package was halted
  due to errors, PASS only if this upload addresses the failure; FAIL if the
  regression is unaddressed. N/A if the package is not currently phasing / was
  never halted.

### Stage F — Finalize

Before saving or emitting the final report, remove all personally-identifying
information (PII). Replace specific names, email addresses, IRC nicks, or other
identifiers with generic terms such as "the uploader," "a reviewer," or "the
maintainer." Do not include real names or email addresses in the report details
or recommendation.

---

## Report template

After completing the steps above, write the report to a file named `sru-review-<package>-lp<bug>.md` (use the primary bug number from the changelog) and emit it as a **Markdown** document using the following structure. The check numbers below are stable and map to the Stage steps above.

```markdown
# SRU Review Report

| Field | Value |
|-------|-------|
| **Package** | `<source-package>` |
| **Tag(s)** | `<queue-tag(s)>` |
| **Reviewer** | <your identifier> |
| **Date** | <YYYY-MM-DD> |

## Summary

**APPROVE / REJECT / NEEDS-INFO** — <one-line verdict>

## Checks

| # | Check | Result |
|---|-------|--------|
| 1 | Bug references in changelog | ✅ PASS / ❌ FAIL / — N/A |
| 2 | Bugs publicly accessible | ✅ PASS / ❌ FAIL / — N/A |
| 3 | Bug references in source.changes | ✅ PASS / ❌ FAIL / — N/A |
| 4 | Minimal change | ✅ PASS / ❌ FAIL / — N/A |
| 5 | No unrelated changes | ✅ PASS / ❌ FAIL / — N/A |
| 6 | DEP-3 patch format | ✅ PASS / ❌ FAIL / — N/A |
| 7 | Correct versioning | ✅ PASS / ❌ FAIL / — N/A |
| 8 | No co-dependent SRU | ✅ PASS / ❌ FAIL / — N/A |
| 9 | Fix in later releases | ✅ PASS / ❌ FAIL / — N/A |
| 10 | Fix in devel release | ✅ PASS / ❌ FAIL / — N/A |
| 11 | New upstream / uscan | ✅ PASS / ❌ FAIL / — N/A |
| 12 | Package-specific procedure | ✅ PASS / ❌ FAIL / — N/A |
| 13 | NEW packages in control | ✅ PASS / ❌ FAIL / — N/A |
| 14 | Maintainer has ubuntu.com email | ✅ PASS / ❌ FAIL / — N/A |
| 15 | No translation changes | ✅ PASS / ❌ FAIL / — N/A |
| 16 | Correct release tasks | ✅ PASS / ❌ FAIL / — N/A |
| 17 | SRU template filled | ✅ PASS / ❌ FAIL / — N/A |
| 18 | Kernel GA & HWE in plan | ✅ PASS / ❌ FAIL / — N/A |
| 19 | Test plan covers usage | ✅ PASS / ❌ FAIL / — N/A |
| 20 | Good user story in plan | ✅ PASS / ❌ FAIL / — N/A |
| 21 | Phasing errors addressed | ✅ PASS / ❌ FAIL / — N/A |

## Details

<!-- For every FAIL or NEEDS-INFO, add a ### heading per check with a concise explanation.
     If all checks pass, write: "All checks passed. No issues identified." -->

## Recommendation

### ✅ APPROVE / ❌ REJECT / ℹ️ NEEDS-INFO

<!-- If APPROVE: one-line confirmation. -->
<!-- If REJECT: state the blocking issue(s) and what the uploader must fix. -->
<!-- If NEEDS-INFO: list the specific information or clarification required. -->
```

Stop after emitting the report.
