# ubuntu-assisted-reviews
Hackathon repo for AI-assisted review for SRU uploads.

## Skills

This repo ships agent [skills](https://agentskills.io) that assist with Ubuntu
package reviews. Each skill lives in its own top-level directory with a
`SKILL.md` entrypoint.

- [`sru-review`](sru-review/SKILL.md) — review an Ubuntu Stable Release Update
  (SRU) from a git-ubuntu queue tag and produce a report with a recommendation.
- `new-review` — review packages in the NEW queue (referenced in `AGENTS.md`;
  not yet implemented).

### `sru-review` layout

- `sru-review/SKILL.md` — the workflow and per-check rubric.
- `sru-review/report-template.md` — the report skeleton the skill fills in.
- `sru-review/scripts/` — helper scripts that do the mechanical, error-prone
  parts (context gathering, `.changes` download, rmadison matrix, Launchpad bug
  queries, phasing status, and an environment preflight). Run
  `sru-review/scripts/check-env.sh` to confirm the required tools
  (`git-ubuntu`, `rmadison`, `distro-info`, `jq`, `curl`, `lynx`) are installed.

## Examples
The [examples](examples) directory contains two reports generated for the same SRU (openssl). One with the MoonshotAI/Kimi-K2.6 model, and another for Claude Sonnet 4.6. Both were given the same skill:

 * [MoonshotAI/Kimi-K2.6](examples/moonshotAI-Kimi-K2.6-sru-review-openssl-lp2130576.md)
 * [Claude Sonnet 4.6](examples/Claude-Sonnet-4.6-sru-review-openssl-lp2130576.md)

## Running with `workshop`

Setup the workspace:

```bash
workshop launch
workshop exec -- claude login
workshop exec -- git config --global gitubuntu.lpuser "$LP_USER"
```

Run the SRU review action:

```bash
workshop run --env CLAUDE_MODEL=$CLAUDE_MODEL -- claude $UBUNTU_SERIES $SOURCE_PACKAGE
```

For example:

```bash
workshop run -i --env CLAUDE_MODEL=claude-sonnet-4-6 -- claude-sru-review noble openssl
```
