# semrel-e2e

Standalone end-to-end test repository for the [semrel](../semrel) release tool
and its plugin ecosystem. This fills the gap tracked as ["End-to-end
integration tests" (Issue #21)](https://github.com/SemRels/semrel/issues/21)
in `semrel/MVP-ROADMAP.md`: `semrel/scripts/local-demo.sh` proves the concept
with one throwaway repo and two plugins; this repo generalizes that pattern
into a persistent, extensible suite covering every plugin category and
several core config features (conditions, prereleases, monorepos, version
ceilings, tag-exists handling).

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

As of the last full run: **22 passed, 3 skipped (no external credentials
available), 0 failed** -- see "Known issues found by this suite" below for
what it took to get there, and "Still not covered" for the 3 remaining
skips and exactly what would close them.

## Real execution, safe by default

Every scenario runs real code against real git repos -- no `--dry-run`. To
keep that safe without needing production credentials on every run,
scenarios split into two groups:

- **Local-only (run by default, never touch anything outside `.work/`).**
  Providers/hooks that need "a remote" push to a local `git init --bare`
  directory instead of GitHub/GitLab/etc. Providers/hooks/publishers that
  need "an HTTP endpoint" hit `scripts/mock-http-server/server.js`, a tiny
  local Node server that logs what it received (provider-gitlab, provider-
  gitea, hook-slack, hook-teams, hook-matrix, hook-jira, publisher-generic-
  http all run for real against it). hook-email runs for real against
  `scripts/mock-smtp-server/server.js`, a minimal local SMTP catcher. This
  covers every plugin category except the parts that are inherently
  external (a real GitHub/Bitbucket release, a real nfpm/oras toolchain and
  OCI registry).
- **External, opt-in (skipped unless you export credentials).**
  `13-provider-external` (github, bitbucket) and `14-hooks-external`
  (slack, as an extra confidence check beyond the local mock) talk to a
  real account and skip per-block unless you export `SEMREL_E2E_*`
  credentials -- read the comment header in each file. `20-publisher-oci`
  needs `SEMREL_E2E_OCI_REF` pointing at a real, already-trusted registry
  (see its header for why a local one can't substitute: the plugin
  hardcodes `oras push` with no `--plain-http`/`--insecure` support).
- `11-packager-nfpm` runs for real once `nfpm` is on PATH -- get it with
  `go install github.com/goreleaser/nfpm/v2/cmd/nfpm@latest` (no
  admin/Docker needed).

`scripts/run-all.sh` treats exit code `77` as skipped, distinct from a real
failure.

## Plugin category coverage

| Category | Scenario(s) | Notes |
|---|---|---|
| Condition | 01, 03, 06, 07, 15 | negative path (06) and all three CI-gate plugins, including their undocumented required token vars (07) |
| Provider | 01, 02, 08, 09, 13\*, 15, 17 | git (local), gitlab+gitea (local mock), github+bitbucket (13, opt-in real) |
| Updater | 02, 03, 04, 05, 16, 23 | every updater plugin in the workspace, incl. two confirmed README/implementation mismatches (05) |
| Generator | 02, 08, 24 | changelog-md, changelog-html, release-notes, plus `commit_changelog: false` handoff to a generator plugin |
| Hook | 09, 14\*, 18, 19 | gitplugin, slack/teams/matrix/jira (local mock), email (local SMTP), slack (14, opt-in real) |
| Publisher | 10, 20\* | generic-http (local mock, real); oci (20, opt-in real -- needs a trusted registry, see below) |
| Packager | 11 | nfpm; real, needs `nfpm` on PATH (`go install`-able, see below) |
| Analyzer | 12 | best-effort smoke test, see scenario header -- not wired into `semrel release` yet |
| Core config | 15, 16, 21, 22, 23 | prerelease channels, workspace independent/lockstep, version_ceiling, tag_exists_strategy |
| Core CLI | 25 | lint, commitlint, doctor, config init/show/validate/set, migrate |

\* opt-in / conditionally skipped -- see the scenario's header comment for exactly what it needs.

### Still not covered

Everything below needs a credential or resource only you can provide --
these are the only 3 scenarios that skip in the last full run, and each
tells you exactly what to export when you run it:

- **`13-provider-external`** (github, bitbucket) -- needs a real account +
  a scratch repo you own. Export `SEMREL_E2E_GITHUB_TOKEN`/`_OWNER`/`_REPO`
  and/or `SEMREL_E2E_BITBUCKET_APP_PASSWORD`/`_USERNAME`/`_WORKSPACE`/`_REPO`
  (see the file header for exact names).
- **`14-hooks-external`** (slack) -- an extra confidence check beyond the
  local-mock coverage in scenario 18. Export
  `SEMREL_E2E_SLACK_WEBHOOK_URL`. (teams/matrix/jira/email don't have an
  external variant here at all -- only slack does; add one following its
  block as a template if you want the same extra check for the others.)
- **`20-publisher-oci`** -- needs `oras` (`go install
  oras.land/oras/cmd/oras@latest`) and `SEMREL_E2E_OCI_REF` pointing at a
  real, already-TLS-trusted registry (ghcr.io/..., a company registry,
  etc.) you're logged into via `oras login`. A local plain-HTTP registry
  was tried and works as a real OCI server, but publisher-oci's own `oras
  push` call has no `--plain-http`/`--insecure` support to talk to one --
  see the scenario header.

`provider-gitlab`/`provider-gitea` (scenario 17) and `hook-teams`/`hook-
matrix`/`hook-jira`/`hook-email` (scenarios 18/19) are exercised for real,
just against a local mock/SMTP catcher rather than a production instance --
that's a deliberate, permanent design choice (see "Real execution, safe by
default" above), not a gap to close.

## Known issues found by this suite

Building and actually running every scenario (not just writing them)
surfaced real bugs and README/implementation drift across the workspace.
Each is documented in the relevant scenario's header comment with exact
file/line references; summarized here:

**semrel core (`semrel/internal/cli/*.go`):**
- `semrel workspace release --config <relative path>` is broken: package
  configs get double-joined against the wrong cwd after `os.Chdir` and fail
  with "path not found". Always pass an absolute `--config` path to
  `workspace release`. (scenario 16)
- `SEMREL_VERSION` passed to pre-tag plugins is wrong for any workspace
  package with a non-trivial `tagPrefix` (e.g. `packages/api@v`): it's built
  from the full tag string instead of the bare version, even though
  `SEMREL_TAG_PREFIX` is exported separately for exactly this purpose.
  Every simple updater plugin writes the literal, un-stripped tag string
  into the version field. (scenario 16)
- `ceiling_strategy: clamp` does not release at `version_ceiling` as
  documented -- it steps down to the next-smaller bump size instead (a
  major bump retries as `current.Minor+1`, a major-or-minor bump retries as
  `current.Patch+1`), which can land well below the ceiling. (scenario 21)
- `semrel workspace release` with `strategy: lockstep` miscomputes the
  shared version: it scrapes `"current_version":"` (no space) out of
  `--output json`, which actually pretty-prints as `"current_version": "`
  (with a space) -- the match always fails, current version silently
  defaults to `0.0.0`, and the "shared next version" is wrong on every run.
  (scenario 23)

**Plugins (README documents a different contract than the code
implements):**
- `updater-terraform` ignores any variable name and blind-regexes the first
  `version = "x"` line; there is no way to target a specific `variable`
  block. (scenario 05)
- `updater-homebrew` only supports `SEMREL_PLUGIN_FILE` (default
  `Formula.rb`) and a `version "x"` line rewrite -- `FORMULA_FILE`,
  `URL_TEMPLATE`, and `SHA256` from its README don't exist in the code.
  (scenario 05)
- `updater-docker` doesn't touch `ARG VERSION=` at all; it rewrites the
  image tag on a Dockerfile's `FROM` line instead, and with no `image` arg
  it matches (and silently corrupts) the *first* `FROM` line in the file --
  including an unrelated base-image pin. (scenario 05)
- `condition-github-actions`/`condition-gitlab-ci`/`condition-gitea-actions`
  each also require an auth-token env var (`GITHUB_TOKEN`/`GH_TOKEN`,
  `CI_JOB_TOKEN`/`GITLAB_TOKEN`, `GITEA_TOKEN`/`CI_JOB_TOKEN`) that isn't
  mentioned in their README's config table. (scenario 07)
- `hook-gitplugin`'s README describes mirroring a release to a *second*
  repository via `SEMREL_PLUGIN_REPO`; the actual code reads no such
  variable and instead re-tags/pushes in whatever directory semrel itself
  is running in -- which collides with the tag semrel's core already
  created unless given a different `SEMREL_PLUGIN_TAG_NAME`. (scenario 09)
- `hook-jira`'s actual required args are `SEMREL_PLUGIN_BASE_URL`/`_EMAIL`/
  `_API_TOKEN`/`_PROJECT_KEY` (Jira Cloud's email+API-token convention),
  not `_TOKEN`/`_PROJECT` as documented. (scenario 18)

None of these were fixed upstream as part of building this suite -- they're
recorded here (and in each scenario's header) as findings for whoever owns
those repos to triage.

## Adding a scenario

Copy the closest existing `scenarios/<NN-name>/run.sh`, `source
scripts/common.sh`, and use its helpers (`build_semrel`, `build_plugin`,
`new_scenario_repo`, `commit_all`, `assert_*`, `start_mock_server`,
`start_mock_smtp_server`, `finish`). Keep one scenario per `run.sh` file so
`run-all.sh`'s prefix filter and pass/fail/skip summary stay meaningful.

## Why this exists as its own repo

`semrel`'s own `tests/e2e/` (per the roadmap) would test the core engine in
isolation. This repo instead exercises the full, real plugin ecosystem
end-to-end -- deliberately living next to (not inside) `semrel/`, since it
depends on every plugin repo as a sibling checkout and shouldn't force
`semrel/`'s own CI to check them all out.
