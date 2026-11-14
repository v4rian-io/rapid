# rapid flows

Every flow is the same for a human and an agent, online and offline. An
agent follows the steps literally; every refusal names the next command.
`rapid` below is the installed rapid on PATH.

## Start a repository

1. Install rapid once on the machine (README, Install), set your gates in
   `.rapid/conf` (setup refuses a gate that runs a `.rapid/tests` or
   `.rapid/lint` script the repository lacks), then `rapid setup`: `.rapid/version`
   pins by default the newest release (`release/v<series>.<n>`) the installed
   clone holds, or with `--pin <tag>` any version or release tag it holds (with
   no release and no `--pin`, setup says so, naming `--pin VERSION`), hooks
   active as stubs
   that run `rapid hook`, main and dev seeded: main from origin's main when
   there is one, else from the root of dev, else HEAD, and pushed when origin
   is set (a refused push publishes nothing). Setup names the setup author as
   the first admin in `.rapid/admins`, the working copy's own file, kept out of
   history by git's local exclude: main is production, and only the owner, an
   admin, promotes.
   When the one who runs setup is not the owner (an agent never is), name the
   owner: `rapid setup --owner <email> [--owner-name <name>]`, at the first setup or
   in any working copy whose `.rapid/admins` names nobody, writes that
   person (the name as a `# <name>` comment after the address), never the
   runner, as the first admin in `.rapid/admins` (setup-owner).
   `rapid setup --require-test` makes every branch state its requirement and
   its test from that first setup. Without the flag a human runner becomes the first admin of the working copy (any setup of a copy that names none),
   and an agent runner writes none and says so.
2. A later change to the gates is a `[MODE]` commit by an admin, on a branch
   of its own. Who may commit and push
   is the repository's own access; rapid keeps no list of authors.
3. Agents: `rapid setup --agent` installs the guard for Claude Code: it
   denies an agent a push to main and a release.
   Without the guard the session is still an agent: `rapid release` refuses
   it, and `rapid doctor` names `rapid setup --agent`.
4. On a forge: `rapid setup --remote` applies the rulesets (dev and main, main
   and `release/*` tags for the admins only, the tags, and
   safety-lockdown, vault-readonly and branch-deletions; with
   `land_pr=required` also GitHub's review rule and the rapid-check and commit-audit statuses on
   dev only) and writes the rapid-check workflow; commit it on a branch. The
   workflow checks every candidate with dev's checker.

## Work on a change (one branch per concern)

1. `rapid branch <kind> <name> -r "<requirement and how its tests verify it>"`
   (or `--ticket CODE-123` to take the requirement from the tracker;
   `--test <test file or scenario name>` writes its `Test:` line). Add
   `Pri:`, `Tests:`, `Code:` or `Status: intent` lines to
   `.rapid/requirements/<name>.md` when the defaults do not fit (RULES.md,
   Requirements register); `rapid check --reqs` prints the register.
   The branch is `pool/v<series>/n<N>.<kind>.<name>`. Opening it pushes
   nothing: its number `n<N>` is taken in this clone, the same form online
   or offline, and its fork point is anchored at
   `safety/v<series>/n<N>.<kind>.<name>` for good; the anchor and the number
   reach origin with the batch's one push, or with a push of the branch.
2. Commit in atomic steps; a change and its test together. A test written
   first and red on purpose carries `Red: <test>` and the next commit turns it
   green. `commit-msg` runs the commit audit: a subject joined by `and`,
   `with`, `plus`, `or`, `then`, `beside`, `+` or `,` is two commits; a `[FIX]` body says `Cause:`
   then `Fix:`; a commit stays under `max_commit_lines`; a behaviour change
   carries its test.
   Opt-in: `rapid commit --smart` has a fresh model context (the claude CLI,
   or `smart_commit_cmd`) compose the message for what is staged, without
   the calling session's context; the hooks check it like any message, and
   a refused one is shown with nothing committed (`--message-only` prints
   it). Without the CLI it stops cleanly.
3. `rapid check` (fast gate on the work tree) as often as you like;
   `rapid check --each` (the commit audit, then the fast gate on every commit)
   or `rapid check --audit` (the audit alone, instant) before landing. Pushing
   the branch to share it has pre-push check the message and the files of
   every commit, with no gate, and a commit
   past `max_commits` is refused before it is written: land the branch and
   start the next.
4. `rapid land --batch`: policy, then every static check at once (size, the message
   of every commit, the commit audit, the requirement and its
   test), each refusal listed before anything is written; then one merge and
   one tag, local, into the open batch, with no gate and no push. Its test record
   says `Gates: deferred to the close of batch <id>`. `rapid land` without `--batch`
   lands the last branch the same way, then tests and pushes the batch (next section). After that push, apart, it
   deletes the branch on origin; where only admins may (rapid-branch-deletions)
   the branch stays, listed by `rapid status` and `rapid doctor`, until an admin
   runs `rapid branch --delete-landed`.

## When dev moved under you

- A branch behind dev: `rapid land` rebases it onto dev itself (the old tip is
  kept under `refs/rapid/preflight/<name>/...`). On a conflict it leaves the branch as it was, names the
  files (also in `<git common dir>/rapid/conflicts/<name>`), starts
  `land_on_conflict` and exits 4; `rapid sync`, resolve, land again.
  `rapid land BRANCH...` lands a list in order and skips a conflicting branch
  (land-rebases).
- `rapid sync` stopped on a conflict: resolve, `git add`, `git rebase
  --continue`, `rapid sync` again; or `git rebase --abort`.
- `rapid sync` never pushes; share the rebased branch with `rapid sync --push`
  (a lease on the copy origin held, `sync-push`), which pre-push checks. A branch push runs no gate: it is transport, and
  the close tests what reaches dev (push-is-transport).
- Two clones landing at once: the loser's atomic push is refused and nothing
  is half-published; `rapid sync`, then `rapid land` again.
- origin's dev holds a commit rapid land did not make (someone pushed past the
  hooks): every verb that would take it refuses, names it, its author and
  the broken invariant, and leaves local dev alone. Tell the owner; once
  origin's dev is repaired, carry on.
- A coworker landed while you sat on dev: `rapid branch` fast-forwards dev in
  every work tree that holds it, so the new branch starts clean on their work.
  If a work tree cannot follow (an untracked file in the way), `rapid branch`
  refuses and names the catch-up command.
- The name landed elsewhere first: `rapid branch --rename <new-name>`, then sync
  and land.

## Batch landing (the only landing path)

Testing each merge buys nothing the final tree does not, so every `rapid land`
lands into the open batch (`batch-land-local`): its merge, version tag, anchor
(whose name carries its number) and vault branch, its test record saying `Gates: deferred to the close of batch <id>`, but locally, offline and
without a gate; nothing reaches origin. `rapid land --batch` stops there and
defers the close; repeat it for every branch but the last. `rapid land` without
`--batch` then closes the batch it landed into, and with no batch open it is a
batch of one through the same path (`land-closes-batch`). The close first runs `gates_each` on the own
tree of every merge of the batch, all at once (scenario `batch-test-records`), and writes each result
into the gate log of that merge. It then runs one gate once on dev's final tree,
`gates_full` (never the fast gate first, `batch-close-one-gate`); on a
pass it pushes every merge, tag and ref in one atomic push. On a failure the
batch stays as it is (`batch-land`): dev, the version tags, the vault branches
and every branch are kept, nothing is pushed, and the close names the
branch that broke it, the first batch merge whose tree fails the gate (with several merges
it runs what failed on each earlier merge tree, all at once, in work trees
added one at a time, `batch-close-worktrees`). The
fix lands as one more branch on top and its `rapid land` closes again on the new
final tree (`batch-one-push`); `rapid land --failed-gates-only` runs again
only the gates that close failed, proving on its own tree only a merge landed
since, and is refused when no close of the batch failed (`batch-close-failed-gates`).
A close under test holds a marker that carries
its own id and removes no other close's marker (`batch-close-marker`). While a batch is open the pre-push hook refuses every push but the
close's own, so a batch is exactly one push; opening a branch pushes nothing
either. `rapid land` never redoes what is done: a push origin refuses keeps the batch
as it is, and `rapid land` again, from the landed branch or from dev, publishes
it without testing the same tree again (`land-closes-batch`); there is no
separate command to retry a close. If origin's dev
moved under the batch, the close puts local dev back and the branches land again
after `rapid sync`; with origin unreachable the gated batch stays local and
`rapid sync --dev` publishes it later.
`rapid land --halt` stops the close under test and keeps the batch
(`land-closes-batch`). `rapid land --prune` is the hand rollback: dev back where the batch began, its
tags and unpublished vault branches gone, the branches unchanged (`batch-land`). Only `rapid land --pr`
publishes a single merge, so it gates that merge itself. A branch that lands while a close is testing stops that test: there is no point finishing a test another one replaces; the land of the last branch closes the new final tree (`batch-join`). Every test stage runs at maximum parallelism by default (every scenario at once; `-j N` or `RAPID_TEST_JOBS` lowers it), prints each failure the moment it happens and, with `test_on_fail` set in `.rapid/conf`, starts that command on the failure at once: spawn a fixer for it while the rest still run.

## Parallel agents

Agents work in their own branches at once; their lands share one test through
the batch above: each lands its branch with `rapid land --batch`, and one
`rapid land` (the last branch, or from dev) gates the final tree and pushes it
all. Two lands racing for one version take it once (the version tag, then
dev's compare-and-swap), and the second stops with dev unchanged; `rapid
sync`, then land again.

## Offline

- `rapid land` with origin unreachable lands locally and says so.
- Back online: `rapid sync --dev`. It fast-forwards to origin, publishes local
  lands in one push, or, when both sides moved, re-lands each local merge on
  top of origin dev through `rapid land --batch` and one close (gates again, next version; the dev
  it replaced stays whole in the snapshot branch `safety/dev-<timestamp>`; a `Fixes:` naming a re-landed commit
  follows it to its new sha).
- A re-land stopped on a conflict: resolve, `git add`, `git cherry-pick
  --continue` (or `--skip`), then `rapid sync --dev --continue`. The plan is
  kept in `.git/rapid-reland` until every land is back; `rapid doctor` reports a
  pending one. `rapid sync --dev --abort` keeps the remaining lands as
  branches not landed yet (sync and land each again); nothing is lost.
- During a re-land never run `rapid land` by hand: it is refused, because the
  plan lands each branch itself. Resolve, then `rapid sync --dev --continue`.
- The link drops during the close's push: dev, the tags and the batch stay;
  `rapid land` again publishes them without a second test. A `land --pr` push
  that drops undoes its tag.

## Verify the forge (framework source)

`bash .rapid/tests/canary/live.sh` (gh signed in with the `repo` and
`workflow` scopes): a run lands run-scoped branches onto one persistent public
canary repository and checks the real forge (C0 to C9); nothing is ever
deleted but the run's own branches not landed yet. `--dry-run` shows the plan,
`--cleanup RUN` removes an interrupted run's branches. A failing check names
what the forge answered.

## Review on a forge

1. `rapid land --pr`: the merge is built and published as the branch's head, and
   the PR is opened (or updated) with the merge subject and body. Reviewers
   approve that exact commit. Exit 3 means it waits.
2. It waits for `land_approvals` approvals given on the merge sha and, with
   `land_pr=required`, for the rapid-check and commit-audit statuses on it (the forge reruns the
   gates and counts the approvals). A new branch commit makes a new merge, so
   earlier approvals stop counting.
3. `rapid land --pr` again moves dev to exactly that merge and tags it in one
   push; after it, apart, it deletes the branch on origin (where only admins
   may, the branch stays). Never use the merge button. With `land_pr=required`
   GitHub itself refuses dev moving to a commit without the approvals and the
   rapid-check status.

With `land_pr=required` GitHub's review rule refuses every push to dev, so
steps 1 and 3 change: the PR head is the branch tip the gates ran on
(approvals and the rapid-check and commit-audit statuses count on that sha),
and once they hold `rapid land --pr` merges through GitHub's merge API with
rapid's own subject and body (merge-once), checks that the merge's parents
are the old dev and the tested head, its tree the Tested-Tree and its
subject rapid's, and only then tags it and pushes the tag. A mismatch leaves
the tag off and says so. The forge's merge button is still never used.

## Release

main is production: publishing is a release reaching main, and only the
owner, an admin listed in `.rapid/admins`, promotes dev to main. dev is integration; pushing dev, branches or tags
is transport, never publishing.

`rapid release`, run by the owner: the owner check (main's own policy), the
release gate on dev's exact tip, `release/<v>` (its message lists the branches
still open, oldest first, and `Released-By:`), the release merge
`[MERGE] dev into main: <v>` on main (the branches since the last release in
its body), one atomic push. The next land opens the next series. When the
forge's main ruleset requires a pull request, the release opens the dev to
main PR and merges it through the forge's API, checks the merge, then
pushes the release tag; exit 3 means the forge is waiting (reviews or
checks): run `rapid release` again once it is mergeable.

- The releases: `git log --first-parent main`.
- Artifacts: set `release_build` (and `gates_artifact`, `release_publish`)
  in `.rapid/conf`. The release builds them on the tag, audits and gates them,
  lists their checksums in the tag and ships them; a failed channel is
  retried with `rapid release --publish <v>`, which ships the same bytes.

- An agent never releases: it runs `rapid release --dry-run` and reports that
  dev is ready; the agent guard denies a real `rapid release`. A dry run the
  policy refuses still runs the release gate and ends with the refusal; it
  never prints a "would release" line (owner-release).
- With `signed=required` the release tag is signed (`git tag -s`): the
  owner needs a signing key, and a tag whose signer is not an admin (keys:
  `.rapid/signers` at main, else git's config) is refused by release,
  pre-push and I5.
- Anyone else is refused with the admins' addresses. A new admin is added
  to `.rapid/admins`, the working copy's own file, excluded from git by default.
- A repository set up by an agent without `--owner` lists no admin, so
  `rapid release` refuses everyone: `rapid setup --owner EMAIL` names the
  owner, and the owner releases. The personal-data lint accepts an address in
  `.rapid/admins` alone.

- The changelog: `rapid changelog [--from <hash>] [<to-hash>]`, generated
  from history up to `<to-hash>` (default dev's tip), after `<hash>` when
  given: the landed merges grouped by the release that first shipped them,
  newest first, one line each with the version, kind/name and the
  requirement. Deterministic, and no CHANGELOG.md is kept: the command is it.
- The release a commit first shipped in: `git tag --contains <sha>
  --sort=v:refname 'release/*'`, first line.

## Ask the history

- `rapid queue` lists every open branch that carries commits dev lacks, in
  landing order (the order of the branch numbers): its commits, how far it is
  behind dev, whether it merges into dev cleanly with the conflicting files
  named, and which other open branches change a file it changes. It changes
  nothing.
- `rapid version` prints the last version on dev; `--next` the version the
  next land takes; `--at <rev>` the version of the land that brought that
  commit into dev. Nothing is stored or counted in a file.
- `rapid release --of <rev>` names the release that first shipped a commit,
  or `unreleased`. It only reads.
- `rapid branch --reject [<branch>] --reason "<why>"` closes the open PR of the
  branch as a rejection with one comment; the branch and its safety anchor are
  kept, and the author lands again through `rapid land --pr`.
- `rapid doctor --deep` runs the doctor, then the repository's own scenarios
  (`.rapid/tests/run.sh`), and fails when the repository carries none.

## Find and undo a regression

- `rapid bisect <good> <bad> -- <test command>`: first the landed branch, then the
  commit inside it; `Red:` commits are skipped, exit 125 skips a commit the
  command cannot test, and a skipped commit that may have broken it is named.
- `git blame` names the author of every line;
  the merge's trailers name the requirement and the gates.
- Undo a landed branch: `rapid branch fix revert-<name>`, `git revert --no-commit -m 1
  <merge>`, restore `.rapid/requirements/<name>.md` (it is never deleted), commit with
  `[REVERT] ...` and `Fixes: <merge>`, land. Land the repaired work as a new
  branch with `Fixes: <revert commit>`.

## Recover and tidy

- A banned file was staged (`pre-commit` names it): `git restore --staged
  <path>` and add it to `.gitignore`. One committed past the hook makes the
  branch push and `rapid land` refuse the branch: rebuild the branch's commits
  without it (it must never reach history), then land.
- Never delete a branch, dev, main or an anchor: rename with `rapid branch
  --rename`; `rapid land` deletes a landed branch itself. A branch never landed
  stays a branch; `rapid status` and `rapid doctor` list the branches not landed yet.
- Every branch ever started, in creation order, landed or not:
  `git for-each-ref --format='%(refname:lstrip=4) %(committerdate:iso)
  %(contents:subject)' refs/remotes/origin/safety` (a plain `git
  fetch` brings the safety and vault branches; the anchor name carries the number).
- Where did a branch start: `git rev-parse origin/safety/v<series>/<number>.<kind>.<name>^1`.
  Anchors are never deleted or moved.
- Where did a landed branch end: `git rev-parse origin/vault/v<series>/<number>.<kind>.<name>`;
  never deleted or moved either.
- Landed branches still on origin (a forge where only admins delete branches):
  `rapid status` lists them; an admin runs `rapid branch --delete-landed`.
- An agent's destructive git (reset --hard, branch -D, rebase, force push)
  needs `<hooks>/rapid/git-preflight.sh <repo> "<reason>"` first; the guard's
  deny says exactly what to run.
- `rapid status` (`--json` for tools): where you are, open branches, last
  version, a pending re-land. `rapid doctor`: the install (`--fix` repairs the
  hooks setting); `rapid doctor --history [--all|--since REV]`: I1 to I9 (in full after the
  last merge this clone verified, unless the checkpoint no longer holds;
  `--all` walks every merge; the merges are checked at once, one worker per
  core, findings in history order), and every exception the
  rules let land (`Untested:`, `Docs: none`, a batch close, no gate) counted
  with its versions;
  `rapid doctor --verify [SINCE]`: every merge's gates rerun on its own tree,
  and every release's gate on the released tree, each merge's stored gate log
  printed beside the rerun.
- What a land's gates printed: `git notes --ref=gates show <merge>` (each
  merge-tree gate's command, exit code, duration and log tail; `git fetch
  origin refs/notes/gates:refs/notes/gates` brings a coworker's).
- `rapid <verb> -h` prints that verb's usage.
- `rapid land --dry-run` and `rapid release --dry-run` change nothing, local dev
  included: when origin's dev is ahead they stop and say to run `rapid sync
  --dev` first.
- A clone that never ran `rapid setup`: `rapid branch`, `commit`, `land`, `sync`
  and `release` refuse and name it; `rapid status` says what is missing; `check`,
  `bisect` and `doctor` work without it (the forge's runner has no hooks).
- `rapid check --review`: an advisory Claude review of the branch's commits
  (`--strict` fails on a finding); skipped without the claude CLI.

## Upgrade rapid

`rapid branch refactor upgrade-rapid`, `rapid upgrade` (it fetches the tags
of the installed rapid and pins the newest release; `rapid upgrade VERSION`
pins that tag, a version tag `v<series>.<n>` included, when it is higher),
commit `.rapid/version`, `rapid land`: the branch lands under the version dev
pins, the next one runs under the new tag. Going back is a branch that writes
the older tag into `.rapid/version` by hand. A tag the clone lacks is refused, naming `git -C <clone> fetch --tags`; under
signed=required a tag whose commit git cannot verify is refused too.
