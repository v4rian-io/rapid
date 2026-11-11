# rapid_tracker: the adapter path, empty for none.
rapid_tracker() {
  local v src=operator p root
  v="${RAPID_TRACKER:-}"
  [ -n "$v" ] || v=$(git config --get rapid.tracker 2>/dev/null || true)
  if [ -z "$v" ]; then v=$(rapid_conf tracker none); src=conf; fi
  case "$v" in
    none) return 0 ;;
    command:?*)
      [ "$src" = operator ] || RAPID_RC=2 rapid_die "the committed conf names tracker '$v'; a command tracker runs an executable, so set it in RAPID_TRACKER or git config rapid.tracker"
      root=$(rapid_root); p="${v#command:}"
      case "$p" in /*) ;; *) p="$root/$p" ;; esac
      if git -C "$root" ls-files --error-unmatch -- "$p" >/dev/null 2>&1; then
        rapid_die "tracker command $p is a file this repository tracks; keep the adapter outside the repository"
      fi
      [ -x "$p" ] || rapid_die "tracker command $p is missing or not executable"
      printf '%s' "$p" ;;
    *) RAPID_RC=2 rapid_die "tracker '$v' is not none or command:<path>" ;;
  esac
}
# rapid_tracker_call OP ARGS...: run the adapter (if any); print its JSON object.
rapid_tracker_call() {
  local a out
  a=$(rapid_tracker)
  if [ -z "$a" ]; then printf '{}'; return 0; fi
  out=$("$a" "$@") || { rapid_warn "tracker $1 failed (exit $?)"; return 1; }
  case "$out" in "{"*"}") ;; *) rapid_warn "tracker $1 did not answer one JSON object"; return 1 ;; esac
  printf '%s' "$out"
}
# rapid_json_str JSON KEY: one top-level string field (no nesting needed here).
rapid_json_str() { sed -nE 's/.*"'"$2"'"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)".*/\1/p' <<<"$1" | sed -n 1p; }
