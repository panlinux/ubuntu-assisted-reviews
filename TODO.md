# TODO

## Done

- ~~Help the agent figure out how to fetch the sources.changes file~~ — now
  handled by `sru-review/scripts/fetch-changes.sh`, which downloads the
  `.changes` file from the unapproved queue and prints `Launchpad-Bugs-Fixed`
  (report check 3).
- ~~use distro-info-data to save time and skip unsupported ubuntu releases~~ —
  `sru-review/scripts/rmadison-matrix.sh` intersects `rmadison` output with
  `ubuntu-distro-info --supported`/`--devel` and drops EOL releases.
- ~~when checking if the fix is available in later ubuntu releases, trust
  launchpad bug tasks to tell us that~~ — `sru-review/scripts/bug-info.sh`
  reports per-series bug task status as corroborating evidence for checks 9/10
  (still compared against the diff / rmadison matrix).

## Remaining

- add opencode support to the workshop actions
- write a similar skill for the NEW queue review (`./new-review`, referenced in
  `AGENTS.md` but not yet present)
