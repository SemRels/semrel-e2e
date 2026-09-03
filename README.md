# semrel-e2e

Standalone end-to-end test repository for the [semrel](../semrel) release tool
and its plugin ecosystem. This fills the gap tracked as ["End-to-end
integration tests" (Issue #21)](https://github.com/SemRels/semrel/issues/21)
in `semrel/MVP-ROADMAP.md`: `semrel/scripts/local-demo.sh` proves the concept
with one throwaway repo and two plugins; this repo generalizes that pattern
into a persistent, extensible suite covering every plugin category and
several core config features (conditions, prereleases, monorepos).

## How it works

Each `scenarios/<NN-name>/run.sh`:

1. builds `semrel` and whichever plugin binaries it needs, straight from the
   sibling repos in the workspace root (`../<plugin-repo>/cmd/plugin`) --
   no registry, no `~/.semrel/plugins`, no network install;
2. creates a fresh throwaway git repository under `.work/`, seeds it with
   commits and fixture files;
3. runs a **real** `semrel release` (or the plugin binary directly, see
   below) -- real tags, real file edits, real git pushes to local remotes;
4. asserts on the result (tags created/absent, file contents, changelog
   text, requests received by a local mock server, ...).

Run everything:

```bash
./scripts/run-all.sh
```

Run a subset (matches by directory-name prefix):

```bash
./scripts/run-all.sh 03 07
```

Run one scenario directly while developing it:

```bash
bash scenarios/03-updater-go/run.sh
```

Env vars:

- `SEMREL_E2E_REBUILD=1` -- force rebuilding semrel + all plugin binaries
  (otherwise they're cached under `.bin/` between runs)
- `SEMREL_E2E_WORKDIR=/some/path` -- where scenario fixture repos are created
  (default: `.work/`, gitignored)

## Real execution, safe by default

Every scenario runs real code against real git repos -- no `--dry-run`. To
keep that safe without needing production credentials on every run,
scenarios split into two groups:

- **Local-only (run by default, never touch anything outside `.work/`).**
  Providers/hooks that need "a remote" push to a local `git init --bare`
  directory instead of GitHub/GitLab/etc. Publishers/hooks that need "an
  HTTP endpoint" hit `scripts/mock-http-server/server.js`, a tiny local
  Node server that just logs what it received. This covers every plugin
  category except the parts that are inherently external (real GitHub
  releases, real Slack messages).
- **External, opt-in (skipped unless you export credentials).** Scenarios
  `13-provider-external` and `14-hooks-external` talk to a real GitHub repo
  / real Slack webhook you own. They call `skip` (exit 77, reported as
  SKIP, not FAIL) when the relevant `SEMREL_E2E_*` env var isn't set. Read
  the comment header in each file before enabling one.

`scripts/run-all.sh` treats exit code `77` as skipped, distinct from a real
failure.

## Plugin category coverage

| Category | Scenario(s) | Notes |
|---|---|---|
| Condition | 01, 03, 06, 07, 15 | includes the negative path (06) and CI-gate plugins (07) |
| Provider | 01, 02, 08, 09, 13\*, 15 | 13 is the opt-in real-GitHub scenario |
| Updater | 02, 03, 04, 05, 16 | every updater plugin in the workspace gets exercised at least once |
| Generator | 02, 08 | changelog-md, changelog-html, release-notes |
| Hook | 09, 14\* | 09 mirrors to a local bare repo; 14 is the opt-in real-Slack scenario |
| Publisher | 10 | `publisher-generic-http`; documented as "planned" upstream, see scenario header |
| Packager | 11 | `packager-nfpm`; skips itself if `nfpm` isn't installed |
| Analyzer | 12 | best-effort smoke test, see scenario header -- not wired into `semrel release` yet |

\* opt-in, skipped by default.

### Plugins/config features not yet covered

- `provider-gitlab`, `provider-gitea`, `provider-bitbucket` -- extend
  `13-provider-external` following its GitHub block as a template.
- `hook-teams`, `hook-matrix`, `hook-email`, `hook-jira` -- extend
  `14-hooks-external` the same way.
- `publisher-oci` -- same "planned upstream" caveat as `publisher-generic-http`;
  add a scenario mirroring `10-publisher-generic-http-mock` once you have a
  local OCI registry (e.g. a `zot`/`registry:2` container) to point it at.
- `version_ceiling` / `ceiling_strategy`, `tag_exists_strategy`, lockstep
  workspace strategy -- core config features without a dedicated scenario
  yet.

## Adding a scenario

Copy the closest existing `scenarios/<NN-name>/run.sh`, `source
scripts/common.sh`, and use its helpers (`build_semrel`, `build_plugin`,
`new_scenario_repo`, `commit_all`, `assert_*`, `finish`). Keep one scenario
per `run.sh` file so `run-all.sh`'s prefix filter and pass/fail/skip summary
stay meaningful.

## Why this exists as its own repo

`semrel`'s own `tests/e2e/` (per the roadmap) would test the core engine in
isolation. This repo instead exercises the full, real plugin ecosystem
end-to-end -- deliberately living next to (not inside) `semrel/`, since it
depends on every plugin repo as a sibling checkout and shouldn't force
`semrel/`'s own CI to check them all out.
