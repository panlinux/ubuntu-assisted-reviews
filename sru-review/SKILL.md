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

## Fetching web resources

Several URLs encountered during review redirect across domains (e.g. `launchpad.net` → `launchpadlibrarian.net`, `ubuntu-archive-team.ubuntu.com` → `phased-updates.ubuntu.com`). The `web_fetch` tool refuses cross-domain redirects, so always use **`curl -sL`** instead for any URL on these domains:

- `launchpad.net` / `launchpadlibrarian.net`
- `ubuntu.com` / `ubuntu-archive-team.ubuntu.com` / `phased-updates.ubuntu.com`
- `canonical.com`

```bash
curl -sL "<url>"
```

If you receive an HTTP 5xx error, **retry up to 3 times** before treating it as a failure.

## Workflow

### 1. Determine supported Ubuntu releases

Before evaluating the upload, establish which Ubuntu releases are still
supported. This list determines for which releases the SRU is required and
which releases must be checked for the presence of the fix.

```bash
# List all supported releases (includes the development release)
ubuntu-distro-info --supported

# Identify the current development release
ubuntu-distro-info --devel
```

Keep this list handy — it is used in later steps (see "Verify upstream /
archive alignment") to scope which releases are relevant when confirming the
fix is present in later supported releases and in the current devel release.

### 2. Fetch the upload

```bash
git ubuntu clone <source-package>
cd <source-package>
git ubuntu queue sync
```

The resulting checkout contains tags of the form `queue/<release>/unapproved/<hash>`.

### 3. Verify bug references

- Open `debian/changelog`. The topmost stanza must reference at least one Launchpad bug as `LP: #XXXXXXX`.
- Verify every referenced bug is **public** (reachable at `https://bugs.launchpad.net/bugs/XXXXXXX` without authentication).
- Locate the `source.changes` file in the Launchpad unapproved queue at:
  `https://launchpad.net/ubuntu/<release>/+queue?queue_state=1`
  (replace `<release>` with the target Ubuntu release name, e.g. `noble`).
  Find the relevant upload in the queue and download the `.changes` file from there.
- Confirm the `source.changes` file also lists the same bug numbers.

### 4. Check changes quality

- The overall change should be **minimal** and focused on fixing the reported bug(s).
- No unrelated changes are present in the diff.
- Any new Debian patch file should conform to the Debian DEP-3 format.
- Package version follows SRU convention (`<oldversion>+esm*` or `<release><number>.<oldversion>`).
- No dependency on another SRU that must land simultaneously.

### 5. Verify upstream / archive alignment

```bash
rmadison -a source <package>
```

- Identify the versions in **later supported releases** and the **current devel release**.
- In the git-ubuntu repository, each Ubuntu release is represented by a tag of the form `pkg/ubuntu/<release>-devel`.
- For each relevant release, compare its changelog/diff against this SRU to confirm the same fix (or an equivalent/superseding fix) is present.
- The fix is present in all **later supported releases**.
- The fix is present in the **current devel release**. The fix being available in `devel-proposed` (the `-proposed` pocket of the development release) is sufficient to satisfy this criterion. If it has not yet migrated to the release pocket, note this in the final report (see the Details section of the report template).
- If a new upstream version is included, confirm `uscan` works and the tarball is verifiable.

### 6. Review packaging specifics

- The maintainer in `debian/control` needs to have an `ubuntu.com` email address.
- Check `debian/control` for **NEW packages**; if any exist, this requires an AA/SRU combined review per [non-standard SRU processes](https://documentation.ubuntu.com/sru/en/latest/explanation/non-standard-processes/#new-queue-in-the-sru-context).
- Verify no changes affect translations.
- If the bug claims a **package-specific procedure**, consult [package-specific SRU instructions](https://documentation.ubuntu.com/sru/en/latest/reference/package-specific/).

### 7. Validate bug & test plan

- On Launchpad, the bug has **Ubuntu release tasks** for every target release.
- The **SRU template** is completely and correctly filled in on each bug.
- The test plan covers **normal usage** of the package, not only the specific code change.
- The test plan tells a coherent **user story**.
- If the bug involves the **kernel**, both **GA and HWE kernels** must be included in the test plan.

### 8. Check phasing status

- Visit <https://phased-updates.ubuntu.com/>.
- If phasing was halted due to errors, confirm the changes in this upload address the failure.

### 9. Sanitize the report

Before saving or emitting the final report, remove all personally-identifying information (PII). Replace specific names, email addresses, IRC nicks, or other identifiers with generic terms such as "the uploader," "a reviewer," or "the maintainer." Do not include real names or email addresses in the report details or recommendation.

## Report template

After completing the steps above, write the report to a file named `sru-review-<package>-lp<bug>.md` (use the primary bug number from the changelog) and emit it as a **Markdown** document using the following structure:

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
| 10 | Fix in devel release | ✅ PASS / ⚠️ PASS (devel-proposed) / ❌ FAIL / — N/A |
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
     If all checks pass, write: "All checks passed. No issues identified."
     If the fix satisfies check 10 only via devel-proposed (i.e. it is present in the
     development release's -proposed pocket but has not yet migrated to the release pocket),
     mark check 10 as "⚠️ PASS (devel-proposed)" in the Checks table above, and
     add a note here stating that the fix in the development release is still pending migration
     from -proposed. -->

## Recommendation

### ✅ APPROVE / ❌ REJECT / ℹ️ NEEDS-INFO

<!-- If APPROVE: one-line confirmation. -->
<!-- If REJECT: state the blocking issue(s) and what the uploader must fix. -->
<!-- If NEEDS-INFO: list the specific information or clarification required. -->
```

Stop after emitting the report.
