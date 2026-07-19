# SRU Review Skill Design Session - Full Conversation

**Date:** 2026-05-13

---

## User: Initial Request

> Consult @sru-checklist and recreate the existing skill in @sru-review/SKILL.md based on the checklist. Do not include the existing skill in your reasoning. The skill should be optimized to avoid excessive token usage regardless of the model being used. The skill should be able to produce a report of its findings in the end with a recommendation.

*(Agent reads `/home/ubuntu/ubuntu-assisted-reviews/sru-checklist` and `/home/ubuntu/ubuntu-assisted-reviews/sru-review/SKILL.md`)*

## Agent: Creates Initial Skill

The agent writes a new `sru-review/SKILL.md` based on the 22-item checklist. The skill includes:
- Prerequisites (git-ubuntu, lrc, rmadison)
- 8 workflow sections
- A structured report template with 21 checks and an APPROVE/REJECT/NEEDS-INFO recommendation

## User: Corrects git-ubuntu Command

> The git-ubuntu command in section 1 is just `git ubuntu clone <source-package>` followed by `cd <source-package>` and `git ubuntu queue sync`. The resulting checkout will contain tags of the form queue/<release>/unapproved/<hash>.

## Agent: Updates Section 1

The agent edits section 1 to:
```bash
git ubuntu clone <source-package>
cd <source-package>
git ubuntu queue sync
```

## User: Requests Full Skill Display

> Please show the full skill again.

## Agent: Displays Full Skill

The agent reads and displays the current contents of `sru-review/SKILL.md`.

## User: Section 3 Modifications

> Let's fix section 3. I have a few modifications for section 3.

## Agent: Asks for Modifications

> What are the modifications you'd like to make to section 3?

## User: Modification 1 - Section Title

> The section title should be "Check changes quality".

## Agent: Updates Title

Changes "Check changelog quality" → "Check changes quality".

## User: Modification 2 - First Bullet

> The first item should be "The overall change should be **minimal** and focused on fixing the reported bug(s)."

## Agent: Updates First Bullet

Changes "The change is minimal" → "The overall change should be minimal".

## User: Modification 3 - Drop Second Bullet

> Drop the second "The changelog cites previous versions..." item

## Agent: Removes Item

Removes the bullet about citing previous versions.

## User: Modification 4 - Add DEP-3 Format

> Add a new item to section 3: "Any new debian patch file should conform to the Debian DEP-3 format."

## Agent: Adds DEP-3 Item

Adds the new bullet point about DEP-3 patch format.

## User: Requests Current Version

> Please print the current version now that section 3 is fixed.

## Agent: Displays Updated Skill

Shows the full current contents of `sru-review/SKILL.md`.

## User: Section 4 - rmadison Command

> For section 4, please use the `rmadison -a source <package>` command to find out about this package's version and Ubuntu releases which carry it.

## Agent: Adds rmadison Command

Adds the command block to section 4.

## User: Asks About Sufficiency

> Will this provide the agent using the skill with sufficient information to use rmadison properly when validating the statements in section 4?

## Agent: Identifies Gap

> No, `rmadison` alone only lists version numbers across releases—it does not tell the agent whether the specific fix from this SRU is actually present in those versions.
>
> To validate those statements, the agent needs additional guidance on how to compare the actual changes. Would you like me to add a follow-up step? For example:
> ```bash
> rmadison -a source <package>
> ```
> - Identify the versions in later supported releases and the current devel release.
> - For each relevant release, compare its changelog/diff against this SRU to confirm the same fix (or an equivalent/superseding fix) is present.
> ...
>
> Or would you prefer a different approach to verifying cross-release alignment?

## User: Approves Approach

> That works. Add that to section 4.

## Agent: Adds Cross-Release Comparison Guidance

Adds the comparison steps to section 4.

## User: Adds Tag Information

> The tags pkg/ubuntu/<release>-devel represent each Ubuntu release. Please add this info when checking if a particular Ubuntu release has that fix.

## Agent: Adds Tag Reference

Adds: "In the git-ubuntu repository, each Ubuntu release is represented by a tag of the form `pkg/ubuntu/<release>-devel`."

## User: Requests Updated Skill

> Print out the updated skill.

## Agent: Displays Full Updated Skill

Shows the complete current contents.

## User: Section 5 - Maintainer Email

> Change the first bullet point of section 5 to "The maintainer in debian/control needs to have an ubuntu.com email address."

## Agent: Updates Section 5 First Bullet

Changes from "Run `update-maintainer`..." to "The maintainer in `debian/control` needs to have an `ubuntu.com` email address."

## User: Section 5 - "claims" Not "involves"

> The last bullet point of section 5 should be "If the bug claims a package-specific procedure[...]"

## Agent: Updates Wording

Changes "If the bug involves" → "If the bug claims".

## User: Drops Section 8

> Drop section 8 entirely.

## Agent: Removes Section 8

Removes "Copyright / licensing review" and the `lrc` prerequisite.

## User: Requests Report Template Consistency Check

> Check the report template at the end and ensure it's consistent with our updated skill.

## Agent: Audits and Fixes Report Template

Finds and fixes inconsistencies:
- Removes "Previous versions cited" (check 4) - no longer in workflow
- Removes "Copyright review (lrc)" (check 21) - section 8 dropped
- Renames "update-maintainer run" → "Maintainer has ubuntu.com email" (check 18)
- Adds "Bug references in source.changes" (check 3) - was in workflow but missing from report
- Adds "DEP-3 patch format" (check 6) - was in workflow but missing from report

## User: Requests Session Save

> Can you save this whole session to a markdown file? We want to include this in the repository for future reference.

## Agent: Saves Summary

Saves `sru-review/SESSION.md` containing a design summary.

## User: Clarifies Request

> I wanted the full conversation between us instead.

## Agent: Saves Full Conversation

*(This file)*

---

## Final Result

The updated `sru-review/SKILL.md` contains:
- 7 workflow sections (down from 8)
- Correct git-ubuntu commands
- rmadison integration for cross-release verification
- Updated packaging specifics (maintainer email, "claims" wording)
- 21-check report template consistent with the workflow
- APPROVE / REJECT / NEEDS-INFO recommendation format
