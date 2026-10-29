#!/usr/bin/env bash
# tests/run.sh [--fast] [--verbose] [-j N] [FILTER] - run the scenario matrix, print one
# line per scenario with its time, then the counts. --fast runs the fast
# subset (the scenarios marked "# fast" on their second line). Scenarios run
# concurrently, up to N at once (-j N, else RAPID_TEST_JOBS, else every selected
# scenario at once, capped at the processes the user may still start, so a run
# never starts more than the machine can run); each scenario runs with its own
# TMPDIR (<run dir>/<name>.tmp, removed with the run). With --verbose each scenario prints a
# progress line on stderr the moment it ends ([n/total], verdict, its time, the
# time elapsed). A failure prints at once on stderr and, with RAPID_TEST_ON_FAIL
# set, starts that command on it at once (args: scenario name, its output file);
# the results still print in file order whatever order they finish in, so the
# output is deterministic. A scenario that dies of a fork failure gave no
# verdict: it runs again alone at the end, and is listed as NORUN (could not
# run), never as FAIL, when no process is available then either.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fast=false; verbose=false; filter=""; jobs="${RAPID_TEST_JOBS:-}"
while [ $# -gt 0 ]; do
  case "$1" in
    --fast) fast=true ;;
    --verbose) verbose=true ;;
    -j) shift; jobs="${1:-}" ;;
    *) filter="$1" ;;
  esac
  shift
done
# a verbose rapid command (land, release, doctor) asks its gate for the progress lines too; the
# scenarios themselves never inherit that
[ -z "${RAPID_VERBOSE:-}" ] || verbose=true; unset RAPID_VERBOSE
# default: maximum parallelism, every selected scenario at once (set once the list is known)
[ -z "$jobs" ] || [[ "$jobs" =~ ^[0-9]+$ ]] || { echo "run.sh: -j needs a number, got '$jobs'" >&2; exit 2; }
# the generated matrix must describe the scenarios that run
bash "$here/gen-scenarios.sh" --check || exit 1
res=$(mktemp -d "${TMPDIR:-/tmp}/rapid-run.XXXXXX"); res=$(cd "$res" && pwd)
trap 'kill $(jobs -p) 2>/dev/null; rm -rf "$res"' EXIT
# the session fixture (lib.sh mkrepo): each set-up repo is built once per run, by the
# first scenario that asks for it, under a lock the others wait on, then copied by all
export RAPID_TEST_FIXTURE="$res/fixture"; mkdir -p "$RAPID_TEST_FIXTURE"
names=()
for s in "$here"/scenarios/*.sh; do
  name=$(basename "$s" .sh)
  [ -z "$filter" ] || case "$name" in *"$filter"*) ;; *) continue ;; esac
  # RAPID_TEST_ONLY: run only the named scenarios (the close narrows its search for the branch that broke it with it)
  [ -z "${RAPID_TEST_ONLY:-}" ] || case " $RAPID_TEST_ONLY " in *" $name "*) ;; *) continue ;; esac
  if $fast && [[ "$(sed -n 2p "$s")" != '# fast'* ]]; then continue; fi
  names+=("$name")
done
total=${#names[@]}
# the processes one scenario may hold at its peak
per=20
# room: the processes this user may still start (the limit of the user minus those running);
# nothing when the limit is unknown or unlimited
room() {
  local lim k cur
  lim=$(ulimit -u 2>/dev/null || true); k=$(sysctl -n kern.maxprocperuid 2>/dev/null || true)
  [[ "$lim" =~ ^[0-9]+$ ]] || lim=""
  if [[ "$k" =~ ^[0-9]+$ ]] && { [ -z "$lim" ] || [ "$k" -lt "$lim" ]; }; then lim=$k; fi
  [ -n "$lim" ] || return 0
  cur=$(ps -U "$(id -u)" -o pid= 2>/dev/null | wc -l | tr -d ' ')
  echo $(( lim - cur ))
}
# every selected scenario at once, never more than the machine can run: the default is capped
# at the room there is; a number the caller gave (-j, RAPID_TEST_JOBS) is taken as given
capped=false
if [ -z "$jobs" ]; then
  jobs=$total; capped=true
  r=$(room)
  if [ -n "$r" ]; then c=$(( r / per )); [ "$c" -ge 1 ] || c=1; [ "$c" -ge "$jobs" ] || jobs=$c; fi
fi
[ "$jobs" -ge 1 ] || jobs=1
t0=$(date +%s); running=0
# run_one NAME: run the scenario, record "<rc> <seconds>" (rc 2: it could not run), print its
# progress line. A scenario that dies of a fork failure gave no verdict: its first such end
# records nothing, it runs again alone once the others have ended.
run_one() {
  local name="$1" s0 rc secs n word second=false
  [ ! -e "$res/$name.again" ] || second=true
  s0=$(date +%s)
  mkdir -p "$res/$name.tmp"
  if TMPDIR="$res/$name.tmp" bash "$here/scenarios/$name.sh" > "$res/$name.out" 2>&1; then rc=0; else rc=1; fi
  if [ "$rc" != 0 ] && grep -E 'fork: Resource temporarily unavailable|fork: retry|[Cc]annot fork|unable to fork' "$res/$name.out" >/dev/null 2>&1; then
    if $second; then rc=2; else : > "$res/$name.again"; return 0; fi
  fi
  secs=$(( $(date +%s) - s0 ))
  echo "$rc $secs" > "$res/$name.rc"
  case "$rc" in 0) word=PASS ;; 2) word=NORUN ;; *) word=FAIL ;; esac
  # one line per scenario the moment it ends, counted under a lock
  until mkdir "$res/.lock" 2>/dev/null; do sleep 0.05; done
  n=$(( $(cat "$res/.n" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$res/.n"
  ! $verbose || printf '[%s/%s] %s  %s  %ss, %ss elapsed\n' "$n" "$total" "$word" "$name" "$secs" "$(( $(date +%s) - t0 ))" >&2
  rmdir "$res/.lock" 2>/dev/null || true
  if [ "$rc" = 1 ]; then
    # a failure is reported the moment it happens, not at the end of the run, and
    # RAPID_TEST_ON_FAIL (if set) starts on it at once, in the background: e.g. a
    # fixer worker. It gets the scenario name and a copy of its output.
    { printf '!! FAIL %s (%ss), live:\n' "$name" "$secs"; tail -n 8 "$res/$name.out" | sed 's/^/      /'; } >&2
    if [ -n "${RAPID_TEST_ON_FAIL:-}" ]; then
      fl="${RAPID_TEST_FAIL_DIR:-${TMPDIR:-/tmp}}/rapid-fail-$name.log"; cp "$res/$name.out" "$fl" 2>/dev/null || true
      ( sh -c "$RAPID_TEST_ON_FAIL" rapid-on-fail "$name" "$fl" </dev/null >/dev/null 2>&1 & )
    fi
  fi
}
for name in ${names[@]+"${names[@]}"}; do
  while [ "$running" -ge "$jobs" ]; do
    wait -n 2>/dev/null || wait "$(jobs -p | head -n 1)" 2>/dev/null
    running=$(jobs -pr | wc -l | tr -d ' ')
  done
  if $capped; then
    # the room is read again before each start: other work on the machine takes processes too
    while [ "$running" -gt 0 ]; do
      r=$(room); [ -n "$r" ] && [ "$r" -lt "$per" ] || break
      sleep 0.2; running=$(jobs -pr | wc -l | tr -d ' ')
    done
  fi
  ( run_one "$name" ) &
  running=$(jobs -pr | wc -l | tr -d ' ')
done
wait
for name in ${names[@]+"${names[@]}"}; do
  if [ -e "$res/$name.again" ] && [ ! -e "$res/$name.rc" ]; then run_one "$name"; fi
done
pass=0; fail=0; failed=""; norun=""
for name in ${names[@]+"${names[@]}"}; do
  read -r rc secs < "$res/$name.rc" || { rc=1; secs=0; }
  if [ "$rc" = 0 ]; then
    pass=$((pass + 1)); printf 'PASS  %-34s %3ss\n' "$name" "$secs"
  elif [ "$rc" = 2 ]; then
    norun="$norun $name"; printf 'NORUN %-34s %3ss\n' "$name" "$secs"
    echo "      could not run: no process available, not a test result"
  else
    fail=$((fail + 1)); failed="$failed $name"; printf 'FAIL  %-34s %3ss\n' "$name" "$secs"
    tail -n 15 "$res/$name.out" | sed 's/^/      /'
  fi
done
printf -- '---- %s passed, %s failed in %ss (%s at once)%s%s\n' "$pass" "$fail" $(( $(date +%s) - t0 )) "$jobs" "${norun:+ (could not run:$norun)}" "${failed:+ (failed:$failed)}"
[ "$fail" = 0 ] && [ -z "$norun" ]
