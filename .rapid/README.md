# rapid

rapid is a software development lifecycle tool for humans and AI agents. It
manages branches, merges, testing and releases; tracks requirements and the
tests that verify them; and protects the repository with git hooks, an AI agent
guard, and GitHub rulesets with CI checks. Fast and flexible, with strict
quality control and full traceability.

## The protocol

- **branch**: a git branch that holds every commit of one unit of work,
  classified by kind (`feature`, `fix`, `r&d`, `refactor`, `docs`, `test`)
  and named `pool/v<series>/n<N>.<kind>.<name>`: `n<N>` is its unique number, assigned
  in creation order, `<name>` the name of the work unit.
- **pool**: the set of active branches: every branch opened and not yet
  landed, by any developer, under `pool/v<series>/`.
- **dev**: the integration branch. Each branch lands on it as exactly one
  merge commit, tagged with the next version (e.g. `v2026.0.47`); dev's
  first-parent history is the record of every landed change.
- **batch**: the branches one developer lands together. Each is merged into
  dev locally; the result is then tested once and pushed in one atomic push.
- **safety**: a permanent ref, `safety/v<series>/n<N>.<kind>.<name>`, to an
  anchor commit on the branch's fork point (the dev commit it started from).
  It keeps the branch's base and number on record.
- **vault**: a permanent ref, `vault/v<series>/n<N>.<kind>.<name>`, to the
  branch's final commit as landed, so its exact contents outlive the branch.
- **main**: main is production. It moves only by a release: a merge of dev
  into main tagged `release/<version>`. By default only the owner (the
  first admin in `.rapid/admins`) releases, and each release opens the next
  series.

The flow:

1. `rapid branch` opens a branch from dev and anchors it. Nothing is pushed.
2. `rapid land --batch` merges it into dev, into the open batch: local, no
   test, no push.
3. `rapid land` lands the last branch and closes the batch: the final tree is
   tested once and everything goes out in one atomic push. With no batch open,
   it is a batch of one.
4. `rapid release` (the owner) merges dev into main. An agent never releases.

Testing and pushing each change separately costs one full run and one push
per change, and only the last tree reaches production anyway. rapid keeps
one merge and one version per change and tests once, on the tree it publishes.

If the test fails, the batch stays, the branch that broke it is named, and the
fix lands as one more branch.

Always true:

- **History is the database.** Versions, branches and requirements are read
  from dev's history; nothing else stores them. Any point can be rebuilt,
  blamed and bisected.
- **Nothing is lost, nothing leaks.** Branches, dev and main are never deleted
  by hand; no secret, key, build output or archive is committed.
- **One requirements register.** `rapid check --reqs` builds it from
  `.rapid/requirements/` on demand; no file holds it, so it cannot drift.
- **One flow.** The same commands work alone or in a team, online or offline,
  with or without a forge.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/v4rian-io/rapid/main/.rapid/install.sh | bash
```

It clones rapid into `~/.rapid` and links `rapid` into `~/.local/bin`.
To clone it elsewhere, set `RAPID_HOME`:

```sh
curl -fsSL https://raw.githubusercontent.com/v4rian-io/rapid/main/.rapid/install.sh | RAPID_HOME=~/tools/rapid bash
```

## In your repository

Once per repository:

```sh
# go to your repo
cd <your-repo>

# set up latest rapid in this repo
rapid setup
```

For each code change:

```sh
# 1. open a branch for the change
rapid branch <kind> <name>

# 2. stage and commit as usual
git add <your files>
git commit -m "..."

# 3. merge into dev, run the tests once, push
rapid land
```

`rapid --help` lists every command; `rapid <command> --help` shows one.

## Basic operation

**Kinds:** `feature`, `fix`, `r&d`, `refactor`, `docs`, `test`.

```sh
rapid branch fix login-timeout
```

**Commit messages:** `[NEW|FIX|REFACTOR|DOCS|TEST|REVERT|HOTFIX|MODE] Capitalised summary`,
12 to 72 characters, one concern per commit. `[NEW]`, `[FIX]`, `[REFACTOR]`,
`[REVERT]` and `[HOTFIX]` need a body line of five words or more; a `[FIX]`
body has a `Cause:` then a `Fix:` paragraph. The hooks check this.

```sh
git commit -m "[NEW] Add passkey login" -m "Users sign in with a passkey instead of a password."
```

**Several changes, one test, one push:**

```sh
# land each branch into the batch: local, no test, no push
rapid land --batch

# land the last one: test the final tree once, push everything
rapid land
```

**Tests:** set your test command in `.rapid/conf` as `gates_full=<command>`.
With `gates_full=none` a land runs no test and says so.

**When the test fails:** land the fix as one more branch, then `rapid land`.
`--failed-gates-only` reruns only what failed, `--halt` stops a running test,
`--prune` drops the batch.

**Requirements:** a branch can state its requirement and the test that verifies
it: `rapid branch <kind> <name> -r "<requirement>" --test <test>`.

**Releases:** by default only the owner runs `rapid release`; `release_who`
and `release_list` in `.rapid/conf` can name others.

## Commands

| Command | Does |
|---|---|
| `rapid setup` | hooks, first admin, main and dev. `--owner` (and `--owner-name`) names the first admin; `--pin` pins a version (default: latest release); `--require-test` makes requirement and test mandatory; `--install` links rapid onto PATH; `--agent` installs the agent guard (`--uninstall`, `--dry-run`, `--prefix`); `--remote` sets forge rulesets and CI (`--repo`, `--dry-run`) |
| `rapid branch` | open a branch (`-r`, `--test`, `--ticket`); `--rename`; `--delete-landed`; `--reject --reason` closes its PR as rejected, keeping the branch (`--mention`, `--dry-run`) |
| `rapid check` | `--gate` a gate on the work tree; `--each` audit and fast gate on every branch commit; `--audit` the commit audit; `--reqs` the requirements register (`--save` to a file); `--merge` the forge's verification for a `land --pr`; `--review` an advisory review (`--strict` fails on a finding); `--land` every static land check of named branches |
| `rapid commit` | `--smart`: a fresh model writes the message for the staged diff, the hooks check it (`--message-only` prints it) |
| `rapid land` | merge into dev with a version tag (`-F` body, `--dry-run`), then close the batch: `gates_each` on each merge's tree, `gates_full` on the final tree, one atomic push. `--batch` defers the close. Rerun, it only does what is still owed. `--failed-gates-only` reruns the failed gates; `--halt` stops a running close; `--prune` resets dev to the batch start; `--pr` lands through review; `--verbose` shows progress |
| `rapid sync` | rebase the branch onto dev, locally (`--push` lease-pushes it); `--dev` reconciles dev with origin after offline work (`--continue`, `--abort`) |
| `rapid release` | the owner by default: release gate, `release/<v>` tag, a `--no-ff` merge of dev into main; with `release_build`, builds, audits and ships artifacts with checksums (`--dry-run`, `--publish`); signed under `signed=required`; `--of` names the release that first shipped a commit; `--verbose` shows progress |
| `rapid changelog` | the changelog from history, by release, one line per merge (`--from`) |
| `rapid bisect` | finds the branch, then the commit, that broke a command |
| `rapid version` | the last version; `--next` the next one; `--at` the version that brought a commit |
| `rapid queue` | open branches in landing order: commits, distance from dev, clean or conflicting merge, overlapping branches (`--json`) |
| `rapid upgrade` | on a branch: fetches the installed rapid's tags and pins a higher version in `.rapid/version`, by default the newest release; an admin commits it as `[MODE]` and lands it |
| `rapid hook` | runs one of rapid's hooks; the repo's hook stubs call it |
| `rapid status`, `rapid doctor` | where you are (`--json`); the install (`--fix`); history invariants (`--history`, `--all`, `--since`, `--history-only`, `--verbose`); `--verify` reruns each merge's gate and compares its log; `--deep` also runs the repo's own tests |

Fifteen verbs, one CLI. `.rapid/lint/docs.sh` checks these docs against the code.

## Read next

- [MANUAL.md](MANUAL.md): every command, flag, conf key, hook and failure, with recovery.
- [RULES.md](RULES.md): branches, commits, merges, versions, invariants, policy.
- [FLOWS.md](FLOWS.md): every flow as steps.
- [DESIGN.md](DESIGN.md): why it is built this way and what it gives up.
- [tests/SCENARIOS.md](tests/SCENARIOS.md): the scenarios that verify it.
- [skill/AGENT.md](skill/AGENT.md): the manual for AI agents.
- [skill/SKILL.md](skill/SKILL.md): the AI agent loader, its lenses (`skill/lenses/`) and the map of every agent rule to its home (`skill/lenses/RULE-MAP.md`).
- [LICENSE](LICENSE): MIT.
