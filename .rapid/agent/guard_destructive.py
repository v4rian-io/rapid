#!/usr/bin/env python3
"""rapid agent hook: PreToolUse(Bash) guard for Claude Code. Deterministic, no model call.

Reads the agent's hook JSON on stdin ({tool_input:{command}, cwd}); a deny is printed as
{hookSpecificOutput:{permissionDecision:"deny",permissionDecisionReason}} with the fix in the reason.
It decides on a real parse of the command. Input it cannot read as JSON, a command it cannot
tokenise, one nested too deeply or one too large to check is denied. Everything else is checked
against the rules below, which name known shapes: a command the rules do not recognise is
allowed. It is a best-effort guard against agent accidents, not a security boundary (see Limits).

Parsing. The command is tokenised as a shell would (quotes, escapes, operators). It is split into
simple commands at && || ; | & ( ) { } newlines and shell keywords; a function body (f() { } and
function f { }) is read as commands. Command substitutions $(...), `...`, <(...) and >(...) are
parsed as commands of their own, and so are the scripts given to bash/sh/zsh -c, eval, trap,
env -S, watch, PROMPT_COMMAND, a heredoc or here-string fed to a shell, a script file run with
bash, sh, source, --rcfile, BASH_ENV or ENV, and the commands tmux, screen, at, batch and
launchctl submit run later. Wrappers (command, builtin, exec, nohup, time, nice, timeout,
gtimeout, ionice, taskpolicy, setsid, flock, stdbuf, env, sudo, doas, xargs, uv/poetry/pipenv run)
are peeled off and a path to git (/usr/bin/git, \\git) counts as git; expect and
crontab, which the guard cannot read, are refused. xargs -I and find -exec placeholders are
unknown values.
Paths are expanded (~, $HOME, and $TMPDIR with the guard's own value), made absolute against the
tracked cwd, normalised (a /tmp/../x path is x) and resolved through symlinks; a path still holding
another variable or a command substitution is unknown and an unknown target of a rule is denied.
An assignment of TMPDIR earlier in the same command is not followed (see Limits).

Rules.
  1. No rm / unlink / shred / find -delete / find -exec rm / xargs rm outside temp roots:
     deletions go to the Trash. A deletion behind an env prefix or xargs is denied.
  2. No destructive git (reset --hard, checkout -f or -- <paths>, restore, switch -f, clean -f,
     force or delete push, branch -D/-M, rebase, filter-branch/filter-repo, stash drop/clear,
     reflog expire, gc --prune, update-ref -d, prune, worktree remove --force, tag -d) without a
     preflight backup that matches the repository now: a preflight-bak-* commit whose parent is the
     current HEAD (a local ref: a preflight never reaches a remote), younger than PREFLIGHT_MAX_AGE_H, with its zip
     still on disk, and no changed path modified after it was taken.
     Exempt: throwaway repos whose worktree AND git common dir live under a temp root; a force push
     from one is exempt only when every remote is itself under a temp root.
     Linked worktrees accept the main repo's preflight; a reset --hard / checkout -f / clean -f
     then still needs the worktree's own preflight when the worktree has changes it would destroy.
     `<installed git-preflight.sh> <repo> ... && <destructive git on that repo>` counts as
     preflighted, only through an unbroken && chain and only when the command is the installed
     preflight script itself.
  3. No push to main (a main destination, --all or --mirror, or a bare push with main checked
     out), no bare --force or +refspec push, no remote repo deletion, no filter-branch -- --all,
     no git -c alias.<name>=!<shell>; git send-pack is checked as the push it is. main is production and only the owner promotes dev to
     it: an agent never runs `rapid release` (its --dry-run is allowed), however it is invoked
     (rapid, .rapid/rapid, a path to it, a renamed copy or a link: any file whose content is rapid's or
     whose directory holds lib/policy.sh, or a shell given one as its script), and never creates, writes
     or pushes a release/<version> tag (git tag, update-ref, push).
  4. No printing of credentials into the transcript: credential files (.env, .netrc, keys, the gh
     token store, cloud and kube configs, /proc/*/environ), gh auth token, keychain passwords,
     git credential fill, git config listings, printenv or echo of a token-named variable, and
     ps with process environments.
  5. Protocol staging and trailer rules: no git add -A / . / :/ / -u, no commit -a, no staging of
     secrets or build output, no Co-Authored-By: Claude trailer on a commit or through
     interpret-trailers, no commit or push --no-verify in a real repository (the hooks are the
     protocol's gates). An agent pushes
     no version tag (v<year>.<n>.<n>) and no --tags / --follow-tags: version tags come only from
     rapid land, and never moves one (git tag -f, update-ref). git's hooks stay where rapid setup put them: no
     core.hooksPath set elsewhere or unset (git config, git -c, GIT_CONFIG_KEY_n), no chmod on a hook stub
     under the git common dir, no chmod and no
     git update-index --chmod on a path under a protected .rapid (git skips a hook it cannot execute),
     and no RAPID_BATCH_CLOSE_PUSH or RAPID_DEVEXEC in front of a command (rapid sets them itself).
  6. Indirection the guard cannot follow is refused: a shell reading its script from a pipe, a
     run-time value as a git subcommand or option on a destructive-capable subcommand, a command
     set through the git -c and GIT_CONFIG_KEY_n keys and the GIT_PAGER / GIT_SSH_COMMAND style
     variables the guard lists (a config file named by GIT_CONFIG_GLOBAL is not read), a --git-dir or
     GIT_DIR it cannot resolve, transport programs (--upload-pack, --receive-pack, --exec, ext::
     and protocol.*.allow=always), config that disarms a safety (clean.requireForce=false), inline
     or stdin-fed interpreter code (any python*, node*, bun, deno eval, perl, ruby, php, lua,
     osascript, uv run python) that deletes files or runs git or a shell, rsync --delete outside a
     temp root, and a bare environment dump typed by name (env, printenv, export -p, set,
     declare -x; not by path). Git long
     options are matched by unique prefix however short, as git does (--h is --hard), and
     single-letter clusters are split (-fu is -f -u, -Df is -D -f).
  7. In-place destruction of an existing file outside the temp roots: truncate, : > file, dd of=,
     cp /dev/null, mv into /dev/null and git --output over it.
  8. Safety anchors stay forever: the branch safety/v<series>/<name> (a branch's fork point, written by rapid branch)
     and vault/v<series>/<name> (its tip as it landed, written by rapid land) are never deleted, moved or
     hand-written, with or without a preflight: update-ref on it, a push that
     deletes it, forces it or sends anything but the anchor itself to it, and a fetch that prunes or
     forces into it are denied in a real repository.
  9. Developers never delete branches: git branch -d/-D/-m/-M, update-ref -d and a deleting push of
     dev, main or a branch are denied in a real repository, preflight or not (rapid branch --rename renames
     a branch, rapid land deletes a landed one, and a branch never landed stays a branch).
 10. No Bash write (a redirection, tee, cp, mv, sed -i and the like) into a protected .rapid or into
     <git common dir>/rapid; conf, admins, version, requirements/ and tests/ excepted.
  Also preflighted as rewrites: reset (any mode) to a commit HEAD does not lead to, amend of a
  pushed commit, checkout of a magic pathspec (:/), interactive clean.
Limits. This is a guard against accidents and casual misuse by an agent, not a sandbox and not
an access control. It matches known command shapes; a shape it does not know (an unlisted wrapper
program, a git transport or plumbing command, a config key, a credential read by another route,
a program the guard cannot read, a path built from a TMPDIR assigned earlier in the same command)
is allowed and can do anything the user's account can. An agent
or input that is hostile is out of scope: contain it with an OS sandbox and server-side rules
(the GitHub rulesets rapid setup --remote applies). The hook entry sets onFailure "block" (Claude Code 2.1.295+), so a timeout or crash of
the hook blocks the call instead of letting it through.
Config: RAPID_BAKS_DIR (bak zips, default $HOME/.rapid/baks; RAPID_GIT_BAKS_DIR is read as a fallback),
PREFLIGHT_MAX_AGE_H (12), GUARD_TMP_ROOTS (colon list that can only narrow the temp exemption).
"""
import fnmatch
import json
import os
import re
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
PF = os.path.join(HERE, "git-preflight.sh")
MAX_CMD = 100000
MAX_DEPTH = 8
MAXH = int(os.environ.get("PREFLIGHT_MAX_AGE_H", "12") or "12")
BAKS = os.environ.get("RAPID_BAKS_DIR") or os.environ.get("RAPID_GIT_BAKS_DIR") or os.path.join(os.path.expanduser("~"), ".rapid", "baks")
HOME = os.path.expanduser("~")
TMPD = (os.environ.get("TMPDIR") or "").rstrip("/")


class Deny(Exception):
    pass


class Unparseable(Exception):
    pass


def deny(reason):
    raise Deny(reason)


def emit_deny(reason):
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse",
                                             "permissionDecision": "deny",
                                             "permissionDecisionReason": reason}}))


# --------------------------------------------------------------------------- tokeniser
OPS = ["&&", "||", ";;", "|&", "&>>", "&>", ">>", "<<<", "<<-", "<<", ">&", "<&", ">|", "<>",
       ";", "|", "&", "(", ")", "<", ">", "\n"]
SEPARATORS = {"&&", "||", ";;", ";", "|", "|&", "&", "(", ")", "\n"}
REDIRS = {">", ">>", ">|", "&>", "&>>", "<", "<>", ">&", "<&", "<<<"}
KEYWORDS = {"if", "then", "elif", "else", "fi", "do", "done", "while", "until", "{", "}", "!",
            "time", "coproc"}


class Word:
    """One shell word: its text with quotes removed, and whether it holds an expansion we
    did not resolve (a variable or a command substitution)."""
    __slots__ = ("text", "dynamic", "raw")

    def __init__(self, text, dynamic, raw):
        self.text, self.dynamic, self.raw = text, dynamic, raw


def _balanced(s, i, open_ch, close_ch):
    """Index just past the close_ch matching s[i] == open_ch, honouring quotes and nesting."""
    depth, j, n = 0, i, len(s)
    while j < n:
        c = s[j]
        if c == "\\":
            j += 2
            continue
        if c == "'":
            k = s.find("'", j + 1)
            if k < 0:
                raise Unparseable("unterminated single quote")
            j = k + 1
            continue
        if c == '"':
            j = _dq_end(s, j)
            continue
        if c == open_ch:
            depth += 1
        elif c == close_ch:
            depth -= 1
            if depth == 0:
                return j + 1
        j += 1
    raise Unparseable("unbalanced %s%s" % (open_ch, close_ch))


def _dq_end(s, i):
    j, n = i + 1, len(s)
    while j < n:
        c = s[j]
        if c == "\\":
            j += 2
            continue
        if c == '"':
            return j + 1
        if c == "$" and j + 1 < n and s[j + 1] == "(":
            j = _balanced(s, j + 1, "(", ")")
            continue
        if c == "`":
            k = s.find("`", j + 1)
            if k < 0:
                raise Unparseable("unterminated backquote")
            j = k + 1
            continue
        j += 1
    raise Unparseable("unterminated double quote")


def tokenize(s, subs):
    """Split shell text into Word and operator tokens. Command substitutions are appended to
    `subs` (their inner text) and leave the word dynamic."""
    toks, i, n = [], 0, len(s)
    while i < n:
        c = s[i]
        if c in " \t":
            i += 1
            continue
        if c == "\\" and i + 1 < n and s[i + 1] == "\n":
            i += 2
            continue
        if c == "#" and (not toks or isinstance(toks[-1], str)):
            k = s.find("\n", i)
            i = n if k < 0 else k
            continue
        op = next((o for o in OPS if s.startswith(o, i)), None)
        if op and not (op in ("<", ">") and i + 1 < n and s[i + 1] == "(" ):
            toks.append(op)
            i += len(op)
            continue
        # a word
        text, raw_start, dynamic = [], i, False
        while i < n:
            c = s[i]
            if c in " \t\n" or (any(s.startswith(o, i) for o in OPS) and not (c in "<>" and i + 1 < n and s[i + 1] == "(")):
                break
            if c == "\\":
                if i + 1 < n:
                    text.append(s[i + 1])
                i += 2
                continue
            if c == "'":
                k = s.find("'", i + 1)
                if k < 0:
                    raise Unparseable("unterminated single quote")
                text.append(s[i + 1:k])
                i = k + 1
                continue
            if c == "$" and i + 1 < n and s[i + 1] == "'":
                k = s.find("'", i + 2)
                if k < 0:
                    raise Unparseable("unterminated $'' quote")
                text.append(s[i + 2:k])
                i = k + 1
                continue
            if c == '"':
                k = _dq_end(s, i)
                inner = s[i + 1:k - 1]
                sub_text, dyn = _expand_dq(inner, subs)
                text.append(sub_text)
                dynamic = dynamic or dyn
                i = k
                continue
            if c == "$" and i + 1 < n and s[i + 1] == "(":
                k = _balanced(s, i + 1, "(", ")")
                inner = s[i + 2:k - 1]
                if inner.startswith("("):  # $(( arithmetic ))
                    text.append("0")
                else:
                    subs.append(inner)
                    text.append("$(...)")
                    dynamic = True
                i = k
                continue
            if c in "<>" and i + 1 < n and s[i + 1] == "(":
                k = _balanced(s, i + 1, "(", ")")
                subs.append(s[i + 2:k - 1])
                text.append("/dev/fd/63")
                dynamic = True
                i = k
                continue
            if c == "`":
                k = s.find("`", i + 1)
                if k < 0:
                    raise Unparseable("unterminated backquote")
                subs.append(s[i + 1:k])
                text.append("$(...)")
                dynamic = True
                i = k + 1
                continue
            if c == "$":
                m = re.match(r"\$(\{[^}]*\}|[A-Za-z_][A-Za-z0-9_]*|[0-9#?$!@*-])", s[i:])
                if m:
                    text.append(m.group(0))
                    i += len(m.group(0))
                    continue
            text.append(c)
            i += 1
        toks.append(Word("".join(text), dynamic, s[raw_start:i]))
    return toks


def _expand_dq(inner, subs):
    """Text of a double-quoted string with substitutions recorded; variables are kept as
    written ($HOME, ${TMPDIR}) for the path expander."""
    out, j, n, dyn = [], 0, len(inner), False
    while j < n:
        c = inner[j]
        if c == "\\" and j + 1 < n and inner[j + 1] in '$`"\\\n':
            out.append(inner[j + 1])
            j += 2
            continue
        if c == "$" and j + 1 < n and inner[j + 1] == "(":
            k = _balanced(inner, j + 1, "(", ")")
            body = inner[j + 2:k - 1]
            if not body.startswith("("):
                subs.append(body)
                out.append("$(...)")
                dyn = True
            else:
                out.append("0")
            j = k
            continue
        if c == "`":
            k = inner.find("`", j + 1)
            subs.append(inner[j + 1:k])
            out.append("$(...)")
            dyn = True
            j = k + 1
            continue
        out.append(c)
        j += 1
    return "".join(out), dyn


# --------------------------------------------------------------------------- heredocs
HEREDOC_RE = re.compile(r"<<(-?)\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\2")
SHELLS = {"bash", "sh", "zsh", "dash", "ksh", "mksh", "fish"}


def split_heredocs(c):
    """Return (command text without heredoc bodies, [(line_text, body)])."""
    lines = c.split("\n")
    out, docs, i = [], [], 0
    while i < len(lines):
        line = lines[i]
        out.append(line)
        i += 1
        for m in HEREDOC_RE.finditer(line):
            tag, strip = m.group(3), m.group(1) == "-"
            body = []
            while i < len(lines) and (lines[i].lstrip("\t") if strip else lines[i]).strip() != tag:
                body.append(lines[i])
                i += 1
            i += 1
            docs.append((line, "\n".join(body)))
    return "\n".join(out), docs


# --------------------------------------------------------------------------- paths
TEMP_DEFAULTS = ["/tmp", "/private/tmp", "/var/folders", "/private/var/folders"]


def _real(p):
    """realpath of the deepest existing ancestor, with the rest appended (normalised)."""
    p = os.path.normpath(p)
    head, tail = p, []
    while head not in ("/", "") and not os.path.exists(head):
        head, t = os.path.split(head)
        tail.insert(0, t)
    base = os.path.realpath(head) if head else "/"
    return os.path.normpath(os.path.join(base, *tail)) if tail else base


def _temp_roots():
    roots = set()
    for r in TEMP_DEFAULTS + ([TMPD] if TMPD else []):
        roots.add(os.path.normpath(r))
        roots.add(_real(r))
    narrow = [x for x in (os.environ.get("GUARD_TMP_ROOTS") or "").split(":") if x]
    if narrow:
        kept = set()
        for r in narrow:
            rr = _real(r)
            if any(_under(rr, t) for t in roots):
                kept.add(rr)
        return roots, kept
    return roots, None


def _under(p, root):
    return p != root and (p + "/").startswith(root.rstrip("/") + "/")


def is_tmp(p, narrowed=True):
    roots, narrow = TEMP_ROOTS
    if not narrowed:
        narrow = None
    rp = _real(p)
    # Checked by where the path really is (a symlink under /tmp to anywhere
    # is not a temp path; re-audit H6).
    if not any(_under(rp, r) for r in roots):
        return False
    if narrow is None:
        return True
    return any(_under(rp, r) for r in narrow)


# Placeholders xargs -I / find -exec substitute at run time ({} and the -I string); a word
# holding one is unknown (round 2 L4).
PLACEHOLDERS = set()


def expand(word, cwd, env):
    """Absolute normalised path for a word, or None when it holds anything unresolved."""
    if word.dynamic or any(ph in word.text for ph in PLACEHOLDERS):
        return None
    t = word.text
    home = env.get("HOME", HOME)
    t = t.replace("${HOME}", home).replace("$HOME", home)
    tmp = env.get("TMPDIR", TMPD) if "TMPDIR" in env else TMPD
    tmp = (tmp or "").rstrip("/")
    if tmp:
        t = t.replace("${TMPDIR}", tmp).replace("$TMPDIR", tmp)
    if t.startswith("~/") or t == "~":
        t = home + t[1:]
    if "$" in t or t.startswith("~"):
        return None
    # Brace expansion ({a,b}, {1..3}) yields other paths at run time (re-audit H6).
    if re.search(r"\{[^{}]*(,|\.\.)[^{}]*\}", t):
        return None
    if not t.startswith("/"):
        if cwd is None:
            return None
        t = os.path.join(cwd, t)
    return os.path.normpath(t)


# --------------------------------------------------------------------------- git helpers
def git(*args, cwd=None):
    try:
        r = subprocess.run(["git"] + list(args), cwd=cwd, capture_output=True, text=True, timeout=8)
    except (OSError, subprocess.TimeoutExpired):
        return None
    return r.stdout.strip() if r.returncode == 0 else None


# --------------------------------------------------------------------------- rules
SECRET_RE = re.compile(r"(\.gcm/store|\.credentials\.json|(^|/)\.auth(/|$)|(^|/)keys/|\.p8$|\.p12$|\.pem$|\.pfx$|\.key$|"
                       r"(^|/)\.env(\.(?!example$|sample$|template$|dist$)[^/]*)?$|(^|/)\.netrc$|(^|/)\.git-credentials$|(^|/)\.npmrc$|(^|/)\.pypirc$|"
                       r"(^|/)id_(rsa|ed25519|ecdsa|dsa)$|(^|/)\.aws/credentials$|(^|/)\.docker/config\.json$|(^|/)\.pgpass$|"
                       r"(^|/)kube-?config$|(^|/)\.kube/config$|(^|/)\.config/gh/hosts\.yml$|(^|/)\.config/git/credentials$|"
                       r"(^|/)\.vault-token$|application_default_credentials\.json$|(^|/)\.config/gcloud/|"
                       r"(^|/)\.ssh/(?!.*\.pub$|known_hosts|config$)|^/proc/[^/]+/environ$|(^|/)token\.json$)")
# Environment variable names that hold a credential (rule 4).
SECRET_VAR_RE = re.compile(r"(TOKEN|SECRET|PASSWORD|PASSWD|API_?KEY|PRIVATE_?KEY|OAUTH|CREDENTIAL|_AUTH\b|AUTH_)", re.I)
READERS = {"cat", "less", "more", "head", "tail", "bat", "strings", "base64", "xxd", "od", "hexdump", "grep", "rg",
           "awk", "sed", "cut", "jq", "python", "python3", "node", "ruby", "perl", "open", "pbcopy", "curl", "tac",
           "nl", "tee", "diff", "cmp", "sort", "uniq", "zcat", "gzip"}
BANNED_STAGE_RE = re.compile(r"(\.DS_Store$|(^|/)\.auth(/|$)|(^|/)keys(/|$)|\.p8$|\.p12$|\.cer$|\.pem$|\.provisionprofile$|"
                             r"\.mobileprovision$|(^|/)build(-[^/]+)?(/|$)|(^|/)node_modules(/|$)|(^|/)\.env$|\.zip$|\.bak$)")
WRAPPERS_NOARG = {"command", "builtin", "exec", "nohup", "time", "caffeinate", "unbuffer", "noglob"}
# Interpreters and the flags that carry inline code.
INTERPRETERS = {"python": ("-c",), "python3": ("-c",), "python2": ("-c",), "perl": ("-e", "-E"),
                "ruby": ("-e",), "node": ("-e", "--eval", "-p", "--print"), "osascript": ("-e",),
                "php": ("-r",), "lua": ("-e",), "Rscript": ("-e",)}
INTERP_DANGER = re.compile(r"rmtree|os\.remove|os\.unlink|os\.rmdir|unlink|rm\s+-|\brm\b|rmdir|\bgit\b|subprocess|os\.system|"
                           r"popen|system\(|exec[lv]?p?e?\(|spawn|child_process|do shell script|`|fs\.rm|rimraf|File\.delete|"
                           r"FileUtils\.rm|shutil|rm(dir)?Sync|unlinkSync|removeSync|Deno\.(remove|run|Command)|execSync|"
                           r"execFile|\.rm\(|\.remove\(|Bun\.(spawn|\$|write)|\$`|truncate|os\.exec|pathlib|"
                           r"\bpty\b|ctypes|__import__|importlib|eval\(|exec\(", re.I)
# Interpreter names by pattern (python3.12, node22, nodejs ...) and the flags that carry code.
INTERP_PATTERNS = [(re.compile(r"python[0-9.]*|pypy[0-9.]*"), ("-c",)), (re.compile(r"node(js)?[0-9]*"), ("-e", "--eval", "-p", "--print")),
                   (re.compile(r"perl[0-9.]*"), ("-e", "-E")), (re.compile(r"ruby[0-9.]*"), ("-e",)),
                   (re.compile(r"php[0-9.]*"), ("-r",)), (re.compile(r"lua(jit)?[0-9.]*"), ("-e",)),
                   (re.compile(r"bun"), ("-e", "--eval", "-p", "--print")), (re.compile(r"osascript"), ("-e",)),
                   (re.compile(r"Rscript"), ("-e",)), (re.compile(r"pwsh|powershell"), ("-c", "-Command", "-command")),
                   (re.compile(r"tclsh|wish"), ()), (re.compile(r"swift"), ("-e",))]
# Runners that put a command under another name and come back later or elsewhere.
RUN_WRAPPERS = {"uv": {"run"}, "uvx": None, "poetry": {"run"}, "pipenv": {"run"}, "pdm": {"run"}, "rye": {"run"},
                "hatch": {"run"}, "conda": {"run"}, "pixi": {"run"}, "mise": {"exec", "x"}, "asdf": {"exec"}}
FRAMEWORK_PARTS = ("/.rapid/",)


def _glob_hits_secret(t):
    """A glob that can expand onto a secret file name (cat .en*, cat *.pem)."""
    if not re.search(r"[*?\[]", t):
        return False
    base = os.path.basename(t)
    for name in (".env", ".env.local", ".env.production", ".netrc", ".git-credentials", ".npmrc", ".pypirc",
                 ".pgpass", "id_rsa", "id_ed25519", "key.pem", "cert.p12", "service.p8", "credentials.json", "kubeconfig"):
        if fnmatch.fnmatchcase(name, base):
            return True
    return False


def check_script_file(word, ctx, env, depth, exec_only=False):
    """Read a shell script run by path and check it like an inline script (re-audit M1).
    The framework's own tools and the installed hooks are trusted as shipped; anything the
    guard cannot read or resolve is refused when it is run as a shell script."""
    p = expand(word, ctx.cwd, env)
    if p is None:
        if exec_only:
            return
        deny("A shell script given by a run-time path blocked (rapid guard). Offending: %s" % ctx.raw)
    rp = _real(p)
    if any(part in rp + "/" for part in FRAMEWORK_PARTS) or rp.startswith(_real(HERE) + "/"):
        return
    try:
        with open(rp, "rb") as f:
            head = f.read(200001)
    except OSError:
        if exec_only:
            return
        deny("A shell script the guard cannot read blocked (rapid guard): %s. Offending: %s" % (p, ctx.raw))
    if exec_only and not re.match(rb"#!\s*\S*(/|env\s+)(ba|z|da|k)?sh\b", head):
        return
    if len(head) > 200000:
        deny("A shell script over 200 kB blocked (rapid guard): too large to check. Offending: %s" % ctx.raw)
    parse_script(head.decode("utf-8", "replace"), Ctx(os.path.dirname(rp), ctx.raw), depth + 1)


class Ctx:
    """State carried across the simple commands of one command line."""

    def __init__(self, cwd, raw):
        self.cwd = cwd
        self.raw = raw
        self.pf_roots = set()      # repo roots preflighted earlier through an unbroken && chain
        self.has_commit = False
        self.piped = False         # the current simple command reads a pipe on stdin
        self.in_pipeline = False   # the current simple command runs in a pipeline (a subshell)


def parse_script(text, ctx, depth=0, inherited_chain=False):
    if depth > MAX_DEPTH:
        deny("Command too deeply nested to check (rapid guard fails closed); split it into plain commands.")
    body, docs = split_heredocs(text)
    subs = []
    toks = tokenize(body, subs)
    for inner in subs:
        parse_script(inner, Ctx(ctx.cwd, ctx.raw), depth + 1)
    # heredocs fed to a shell are commands too
    for line, doc in docs:
        lt = tokenize(line.split("<<")[0], [])
        words = [t.text for t in lt if isinstance(t, Word)]
        if words and any(os.path.basename(w) in SHELLS for w in words):
            parse_script(doc, Ctx(ctx.cwd, ctx.raw), depth + 1)
    seg, sep, stack = [], "^", []
    for t in toks + ["\n"]:
        if isinstance(t, str) and t in SEPARATORS:
            if seg:
                ctx.piped = sep == "|"
                ctx.in_pipeline = ctx.piped or t in ("|", "|&")
                run_segment(seg, sep, ctx, depth)
                ctx.piped = ctx.in_pipeline = False
            seg = []
            # A ( ... ) subshell keeps its directory changes to itself (re-audit H6).
            if t == "(":
                stack.append(ctx.cwd)
            elif t == ")" and stack:
                ctx.cwd = stack.pop()
            sep = "&&" if t == "&&" else ("|" if t in ("|", "|&") else ";")
            continue
        seg.append(t)


def split_redirs(seg):
    words, redirs, i = [], [], 0
    while i < len(seg):
        t = seg[i]
        if isinstance(t, str):
            if t in REDIRS or t in ("<<", "<<-"):
                target = seg[i + 1] if i + 1 < len(seg) and isinstance(seg[i + 1], Word) else None
                redirs.append((t, target))
                i += 2
                continue
            i += 1
            continue
        # fd-number redirections: the number is glued to the operator in shell (2>&1)
        if re.fullmatch(r"[0-9]+", t.raw) and i + 1 < len(seg) and isinstance(seg[i + 1], str) and seg[i + 1] in REDIRS:
            i += 1
            continue
        words.append(t)
        i += 1
    return words, redirs


def run_segment(seg, sep, ctx, depth):
    if sep != "&&":
        ctx.pf_roots = set()
    words, redirs = split_redirs(seg)
    # drop shell keywords that open a compound command; `function NAME` opens a body whose
    # commands follow in this segment and the next ones, so only the two words go (round 2 H1)
    while words:
        if words[0].text in KEYWORDS and not words[0].dynamic:
            words = words[1:]
        elif words[0].text == "function" and not words[0].dynamic:
            words = words[2:]
        else:
            break
    if not words:
        check_truncating_redirs(redirs, ctx, {})
        return
    if words[0].text in ("for", "select", "case") or re.fullmatch(r"[^()]+\)", words[0].text):
        return
    env, envprefix = {}, False
    while words and re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*=.*", words[0].text, re.S):
        k, v = words[0].text.split("=", 1)
        env[k] = v
        envprefix = True
        words = words[1:]
    if not words:
        return
    check_command(words, redirs, env, envprefix, ctx, depth, xargs=False)


def peel(words, env):
    """Strip wrappers; returns (words, env, xargs, script_texts)."""
    xargs = False
    while words:
        name = os.path.basename(words[0].text)
        if name in WRAPPERS_NOARG:
            words = words[1:]
            while words and words[0].text.startswith("-") and words[0].text != "-":
                words = words[1:]
            continue
        if name == "nice":
            words = words[1:]
            if words and words[0].text == "-n":
                words = words[2:]
            elif words and re.fullmatch(r"-[0-9]+", words[0].text):
                words = words[1:]
            continue
        if name == "timeout":
            words = words[1:]
            while words and words[0].text.startswith("-"):
                words = words[2:] if words[0].text in ("-s", "-k", "--signal", "--kill-after") else words[1:]
            words = words[1:]  # duration
            continue
        if name == "script":
            # script [-aqkF...] [-t time] [file [command ...]]: the command runs (re-audit M1)
            words = words[1:]
            while words and words[0].text.startswith("-"):
                words = words[2:] if words[0].text in ("-t", "-T") else words[1:]
            words = words[1:]  # the typescript file
            continue
        if name == "stdbuf":
            words = words[1:]
            while words and words[0].text.startswith("-"):
                words = words[1:]
            continue
        if name in ("sudo", "doas"):
            words = words[1:]
            while words and words[0].text.startswith("-"):
                words = words[2:] if words[0].text in ("-u", "-g", "-C", "-D", "-h", "-p", "-r", "-t", "-U") else words[1:]
            continue
        if name == "env":
            words = words[1:]
            while words:
                t = words[0].text
                if t in ("-u", "--unset", "-C", "--chdir"):
                    words = words[2:]
                elif t in ("-S", "--split-string") and len(words) > 1:
                    return words[2:], env, xargs, [words[1].text + " " + " ".join(w.raw for w in words[2:])]
                elif t.startswith("-"):
                    words = words[1:]
                elif re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*=.*", t, re.S):
                    k, v = t.split("=", 1)
                    env[k] = v
                    words = words[1:]
                else:
                    break
            continue
        if name == "xargs":
            xargs = True
            words = words[1:]
            while words and words[0].text.startswith("-"):
                t = words[0].text
                if t in ("-I", "--replace") and len(words) > 1:
                    PLACEHOLDERS.add(words[1].text)
                elif t.startswith("-I") and len(t) > 2:
                    PLACEHOLDERS.add(t[2:])
                elif t == "-i" or t.startswith("--replace="):
                    PLACEHOLDERS.add(t.split("=", 1)[1] if "=" in t else "{}")
                words = words[2:] if t in ("-I", "-n", "-P", "-L", "-d", "-E", "-s", "-a", "--max-args", "--max-procs",
                                           "--delimiter", "--arg-file", "--replace") else words[1:]
            continue
        # deferred and detached runners (round 2 M5): the command they run is the rest
        if name in ("gtimeout",):
            words = words[1:]
            while words and words[0].text.startswith("-"):
                words = words[2:] if words[0].text in ("-s", "-k", "--signal", "--kill-after") else words[1:]
            words = words[1:]
            continue
        if name in ("ionice", "taskpolicy", "chrt", "setsid", "flock", "cpulimit", "unshare", "firejail", "systemd-run",
                    "chpst", "daemonize", "faketime", "torsocks", "proxychains", "proxychains4", "catchsegv", "valgrind",
                    "strace", "ltrace", "dtruss", "lldb", "gdb"):
            words = words[1:]
            while words and words[0].text.startswith("-"):
                t = words[0].text
                words = words[2:] if t in ("-c", "-n", "-p", "-b", "-t", "-g", "-l", "-u", "-e", "-o", "-w", "-E") \
                    and len(words) > 1 and not words[1].text.startswith("-") else words[1:]
            if name in ("flock", "chrt", "faketime") and words:
                words = words[1:]  # the lock file, priority or time
            continue
        if name in RUN_WRAPPERS:
            subs = RUN_WRAPPERS[name]
            words = words[1:]
            if subs is not None:
                if not words or words[0].text not in subs:
                    break
                words = words[1:]
            while words and words[0].text.startswith("-"):
                words = words[1:]
            continue
        break
    return words, env, xargs, []


def check_command(words, redirs, env, envprefix, ctx, depth, xargs):
    bare = [w.text for w in words]
    if bare in (["env"], ["printenv"], ["export", "-p"], ["export"], ["set"], ["declare", "-x"]):
        deny("Printing the whole environment blocked (rapid guard): it carries tokens into the transcript. Print the "
             "one variable you need. Offending: %s" % ctx.raw)
    words, env, wx, scripts = peel(words, env)
    xargs = xargs or wx
    # rapid sets these two for its own child processes only: the first opens the one-push guard of an
    # open batch, the second makes a branch's own hooks check it instead of dev's
    for k in ("RAPID_BATCH_CLOSE_PUSH", "RAPID_DEVEXEC"):
        if k in env:
            deny("%s blocked (rapid guard): rapid sets it for its own child processes; set by hand it switches a "
                 "check off (the one push of an open batch, the checking of a branch by dev's framework). "
                 "Offending: %s" % (k, ctx.raw))
    for sc in scripts:
        parse_script(sc, Ctx(ctx.cwd, ctx.raw), depth + 1)
    if not words:
        return
    first = words[0]
    name = os.path.basename(first.text)
    if first.dynamic or "$" in name:
        deny("Command name is computed at run time (%s); the rapid guard cannot check it. Run the command directly." % first.raw)
    args = words[1:]

    # export and unset run nothing by themselves
    if name in ("export", "unset"):
        return

    # rule 3: main is production; only the owner promotes dev to main
    if _rapid_release(args) and _is_rapid_program(first, ctx, env):
        deny(RELEASE_MSG % ctx.raw)
    # Shell start-up files and prompt hooks run code before the command (round 2 M5).
    for k in ("BASH_ENV", "ENV", "PROMPT_COMMAND", "ZDOTDIR", "PS4"):
        if k in env:
            if k == "PROMPT_COMMAND":
                parse_script(env[k], Ctx(ctx.cwd, ctx.raw), depth + 1)
            elif k == "PS4":
                if "$(" in env[k] or "`" in env[k]:
                    deny("PS4 with a command substitution runs code (rapid guard). Offending: %s" % ctx.raw)
            else:
                check_script_file(Word(env[k], "$" in env[k], env[k]), ctx, env, depth)

    # trap bodies run later in this shell: read them like eval (round 2 H1)
    if name == "trap":
        rest = [w for w in args if w.text not in ("--",)]
        if rest and rest[0].text not in ("-l", "-p", "-"):
            if rest[0].dynamic:
                deny("A trap with a run-time body blocked (rapid guard): the guard cannot check it. Offending: %s" % ctx.raw)
            parse_script(rest[0].text, Ctx(ctx.cwd, ctx.raw), depth + 1)
        return

    # Detached and scheduled runners (round 2 M5): their command is read like any other.
    if name == "tmux":
        _check_tmux(args, ctx, depth)
        return
    if name == "screen":
        rest, i = list(args), 0
        while rest and rest[0].text.startswith("-"):
            t = rest[0].text
            if t in ("-X", "-Q"):
                deny("screen -X sends keystrokes or commands the guard cannot check (rapid guard). Offending: %s" % ctx.raw)
            rest = rest[2:] if t in ("-S", "-c", "-p", "-t", "-e", "-h", "-T", "-s", "-Logfile") else rest[1:]
        if rest:
            check_command(rest, [], dict(env), envprefix, ctx, depth, xargs)
        return
    if name in ("at", "batch"):
        texts = [w.text for w in args]
        if "-f" in texts and texts.index("-f") + 1 < len(args):
            check_script_file(args[texts.index("-f") + 1], ctx, env, depth)
        here = [t for op, t in redirs if op == "<<<" and t is not None]
        src = [t for op, t in redirs if op == "<" and t is not None]
        if here:
            parse_script(here[0].text, Ctx(ctx.cwd, ctx.raw), depth + 1)
        elif src:
            check_script_file(src[0], ctx, env, depth)
        elif ctx.piped:
            deny("%s reading its job from a pipe blocked (rapid guard): the guard cannot see it. Offending: %s" % (name, ctx.raw))
        return
    if name == "launchctl" and args and args[0].text in ("submit", "asuser", "bsexec"):
        texts = [w.text for w in args]
        rest = args[texts.index("--") + 1:] if "--" in texts else (args[2:] if args[0].text in ("asuser", "bsexec") else [])
        if not rest:
            deny("launchctl %s runs a program the guard cannot see (rapid guard). Offending: %s" % (args[0].text, ctx.raw))
        check_command(rest, [], dict(env), envprefix, ctx, depth, xargs)
        return
    if name == "launchctl" and args and args[0].text == "getenv" and any(SECRET_VAR_RE.search(w.text) for w in args[1:]):
        deny("Printing a credential variable blocked (rapid guard, rule 4). Offending: %s" % ctx.raw)
    if name in ("expect", "unbuffer") and args and name == "expect":
        deny("expect runs a script the guard cannot check (rapid guard); run the commands directly. Offending: %s" % ctx.raw)
    if name in ("crontab",) and any(w.text not in ("-l",) for w in args):
        deny("crontab installs commands that run later; the guard cannot check them (rapid guard). Offending: %s" % ctx.raw)

    # rule 4: commands whose output is a credential (round 2 M6)
    if name == "gh" and [w.text for w in args[:2]] == ["auth", "token"] or \
            name == "gh" and [w.text for w in args[:2]] == ["auth", "status"] and any(w.text in ("-t", "--show-token") for w in args):
        deny("Printing the gh token blocked (rapid guard, rule 4): let gh use it, or read it into a variable. Offending: %s" % ctx.raw)
    if name == "security" and args and re.match(r"find-(generic|internet)-password|dump-keychain|export", args[0].text) \
            and (any(w.text in ("-w", "-g") for w in args) or args[0].text in ("dump-keychain", "export")):
        deny("Printing a keychain secret blocked (rapid guard, rule 4). Offending: %s" % ctx.raw)
    if name == "printenv" and any(SECRET_VAR_RE.search(w.text) for w in args):
        deny("Printing a credential variable blocked (rapid guard, rule 4): use it, never print it. Offending: %s" % ctx.raw)
    if name in ("echo", "printf", "print") and any(re.search(r"\$\{?([A-Za-z_][A-Za-z0-9_]*)", w.raw)
                                                   and SECRET_VAR_RE.search(" ".join(re.findall(r"\$\{?([A-Za-z_][A-Za-z0-9_]*)", w.raw)))
                                                   for w in args):
        to_file = any(op in (">", ">>", ">|") and tgt is not None and tgt.text not in ("/dev/stdout", "/dev/stderr", "/dev/tty")
                      for op, tgt in redirs)
        if not to_file and not ctx.piped and not ctx.in_pipeline:
            deny("Printing a credential variable blocked (rapid guard, rule 4): use it, never print it. Offending: %s" % ctx.raw)
    if name == "ps" and any((not w.text.startswith("-") and re.fullmatch(r"[a-zA-Z]*e[a-zA-Z]*", w.text))
                            or re.fullmatch(r"-[a-zA-Z]*E[a-zA-Z]*", w.text)
                            or (sys.platform == "darwin" and re.fullmatch(r"-[a-zA-Z]*e[a-zA-Z]*", w.text)) for w in args):
        deny("ps with process environments blocked (rapid guard, rule 4): it prints other processes' tokens. Offending: %s" % ctx.raw)

    # In-place destruction of an existing file outside the temp roots (round 2 L3).
    if name in (":", "true", "false"):
        check_truncating_redirs(redirs, ctx, env)
    if name == "truncate":
        _check_clobber([w for w in args if not w.text.startswith("-") and not re.fullmatch(r"[0-9]+[KMGkmg]?", w.text)],
                       ctx, env, "truncate")
    if name == "dd":
        _check_clobber([Word(w.text[3:], w.dynamic, w.raw) for w in args if w.text.startswith("of=")], ctx, env, "dd of=")
    if name == "cp" and any(w.text == "/dev/null" for w in args):
        _check_clobber([w for w in args if not w.text.startswith("-") and w.text != "/dev/null"][-1:], ctx, env, "cp /dev/null")
    if name == "mv" and args and args[-1].text == "/dev/null":
        check_deletion([w for w in args[:-1] if not w.text.startswith("-")], ctx, env, envprefix, xargs, words)

    # interpreters given a script
    if name in SHELLS or name in ("eval", "source", ".", "watch"):
        script, sfile = None, None
        if name == "eval" or name == "watch":
            rest = [w for w in args if not (name == "watch" and w.text.startswith("-"))]
            if any(w.dynamic for w in rest):
                deny("eval of a run-time value blocked (rapid guard): the guard cannot check it. Offending: %s" % ctx.raw)
            script = " ".join(w.text for w in rest)
        elif name in ("source", "."):
            sfile = args[0] if args else None
        else:
            # Shell options: clusters (-ec, -lec, +x), -o/+o NAME pairs and -- may precede
            # the script (re-audit H1); -c anywhere in a cluster makes the first operand a script.
            i, have_c, stdin_flag, done = 0, False, False, False
            while i < len(args):
                t = args[i].text
                if not done and t == "--":
                    done = True
                    i += 1
                    continue
                if not done and t in ("--rcfile", "--init-file") and i + 1 < len(args):
                    check_script_file(args[i + 1], ctx, env, depth)
                    i += 2
                    continue
                if not done and t in ("-o", "+o", "-O", "+O"):
                    i += 2
                    continue
                if not done and re.fullmatch(r"[-+][A-Za-z]+", t):
                    if t[0] == "-" and "c" in t[1:]:
                        have_c = True
                    if t[0] == "-" and "s" in t[1:]:
                        stdin_flag = True
                    i += 1
                    continue
                if not done and t.startswith("--"):
                    i += 1
                    continue
                if have_c:
                    if args[i].dynamic:
                        deny("A shell script computed at run time blocked (rapid guard). Offending: %s" % ctx.raw)
                    script = args[i].text
                elif not stdin_flag:
                    sfile = args[i]
                break
            if script is None and sfile is None:
                # The script comes from stdin: a here-string is checked, a pipe or a file the guard
                # cannot see is refused (echo ... | bash, curl ... | sh; re-audit H1).
                here = [t for op, t in redirs if op == "<<<" and t is not None]
                src = [t for op, t in redirs if op == "<" and t is not None]
                if here:
                    if here[0].dynamic:
                        deny("A shell fed a run-time value blocked (rapid guard). Offending: %s" % ctx.raw)
                    script = here[0].text
                elif src:
                    sfile = src[0]
                elif ctx.piped:
                    deny("A shell reading its script from a pipe blocked (rapid guard): the guard cannot see what it "
                         "runs. Write the commands out, or save the script and run it as a file. Offending: %s" % ctx.raw)
        if script:
            parse_script(script, Ctx(ctx.cwd, ctx.raw), depth + 1)
        if sfile is not None and _is_rapid_program(sfile, ctx, env):
            rest = args[[w is sfile for w in args].index(True) + 1:] if any(w is sfile for w in args) else []
            if _rapid_release(rest):
                deny(RELEASE_MSG % ctx.raw)
        if sfile is not None:
            check_script_file(sfile, ctx, env, depth)
        return

    # A script run by its path is read like an inline script (re-audit M1); the
    # framework's own tools and the installed hooks are trusted as shipped.
    if "/" in first.text and not first.dynamic:
        check_script_file(first, ctx, env, depth, exec_only=True)

    # Other interpreters given inline code: refuse code that deletes or runs git or a
    # shell, which the guard cannot check (re-audit M1).
    flags = INTERPRETERS.get(name)
    if flags is None:
        for pat, fl in INTERP_PATTERNS:
            if pat.fullmatch(name):
                flags = fl
                break
    if name == "deno" and args and args[0].text == "eval":
        flags = ("eval",)
    if flags is not None:
        code = []
        letters = {f[1] for f in flags if re.fullmatch(r"-[A-Za-z]", f)}
        for j, w in enumerate(args):
            if (w.text in flags or (re.fullmatch(r"-[A-Za-z]{2,}", w.text) and set(w.text[1:]) & letters)) and j + 1 < len(args):
                if args[j + 1].dynamic:
                    deny("Inline %s code computed at run time blocked (rapid guard). Offending: %s" % (name, ctx.raw))
                code.append(args[j + 1].text)
            elif any(w.text.startswith(f + "=") for f in flags if f.startswith("--")):
                code.append(w.text.split("=", 1)[1])
        # code on stdin: python3 - <<< '...', node < file, echo ... | python3 (round 2 M4)
        operands = [w for w in args if not w.text.startswith("-") or w.text == "-"]
        if not code and (not operands or operands[0].text == "-"):
            here = [t for op, t in redirs if op == "<<<" and t is not None]
            src = [t for op, t in redirs if op == "<" and t is not None]
            if here:
                code.append(here[0].text)
            elif src:
                pth = expand(src[0], ctx.cwd, env)
                try:
                    code.append(open(pth, errors="replace").read(200000) if pth else "")
                except OSError:
                    deny("%s reading code the guard cannot open blocked (rapid guard). Offending: %s" % (name, ctx.raw))
            elif ctx.piped:
                deny("%s reading its code from a pipe blocked (rapid guard): the guard cannot see it. Offending: %s"
                     % (name, ctx.raw))
        if any(INTERP_DANGER.search(c) for c in code):
            deny("Inline %s code that deletes files or runs git or a shell blocked (rapid guard): the guard cannot "
                 "check it. Run the equivalent shell command directly. Offending: %s" % (name, ctx.raw))

    # rsync --delete removes files under its destination (re-audit M1)
    if name == "rsync" and any(w.text.startswith("--del") or w.text in ("--remove-source-files",) for w in args):
        pos = [w for w in args if not w.text.startswith("-")]
        check_deletion(pos[-1:] if pos else [], ctx, env, envprefix, xargs, words)

    # cd tracking. In a pipeline each command runs in a subshell, so a cd there moves
    # nothing; cd -, popd and run-time targets leave the directory unknown (re-audit H6).
    if name in ("cd", "pushd", "popd"):
        if ctx.in_pipeline:
            return
        if name == "popd" or (args and args[0].text in ("-", "+", "-0", "+0")):
            ctx.cwd = None
        elif args:
            ctx.cwd = expand(args[0], ctx.cwd, env)
        else:
            ctx.cwd = HOME
        return

    # chained preflight: the installed git-preflight.sh itself, never a word that merely names it
    if name == "git-preflight.sh":
        p = expand(first, ctx.cwd, env) if "/" in first.text else None
        if p and _same_file(p, PF) and args:
            r = expand(args[0], ctx.cwd, env)
            root = git("rev-parse", "--show-toplevel", cwd=r) if r and os.path.isdir(r) else None
            if root:
                ctx.pf_roots.add(_real(root))
        return

    # rule 4: credential echo
    if name in READERS:
        to_file = any(op in (">", ">>", ">|", "&>", "&>>") and tgt is not None and not tgt.text.startswith("&")
                      and tgt.text not in ("/dev/stdout", "/dev/stderr", "/dev/tty", "/dev/fd/1", "/dev/fd/2")
                      for op, tgt in redirs)
        inputs = [t for op, t in redirs if op == "<" and t is not None]
        for w in list(args) + inputs:
            if (SECRET_RE.search(w.text) or _glob_hits_secret(w.text)) and not to_file:
                deny("Credential echo blocked: '%s' on a secret path would print the secret into the transcript. "
                     "Read it into a shell variable or let the consuming tool read the file itself. Offending: %s"
                     % (name, " ".join(x.raw for x in words)))

    # rule 6: shell writes into a protected .rapid
    check_bash_writes(name, args, redirs, ctx, env)

    # find: -delete and -exec
    if name == "find":
        texts = [w.text for w in args]
        if "-delete" in texts:
            check_deletion([w for w in args if not w.text.startswith("-") and w.text not in ("(", ")", "!")][:1] or args[:1],
                           ctx, env, envprefix, True, words)
        for i, t in enumerate(texts):
            if t in ("-exec", "-execdir", "-ok", "-okdir"):
                PLACEHOLDERS.add("{}")
                inner = []
                for w in args[i + 1:]:
                    if w.text in (";", "+"):
                        break
                    inner.append(w)
                if inner:
                    check_command(inner, [], dict(env), envprefix, ctx, depth, xargs=True)
        return

    # rule 1: deletions
    if name in ("rm", "unlink", "shred", "srm"):
        targets = [w for w in args if not (w.text.startswith("-") and len(w.text) > 1)]
        check_deletion(targets, ctx, env, envprefix, xargs, words)
        return

    # rule 3: remote repo deletion
    if name == "gh":
        t = [w.text for w in args]
        joined = " ".join(t)
        if t[:2] == ["repo", "delete"] or (t[:1] == ["api"] and re.search(r"(-X|--method)\s*=?\s*DELETE", joined, re.I)
                                           and re.search(r"(^|\s)/?repos/[^/\s]+/[^/\s]+/?(\s|$)", joined)):
            deny("Remote repo deletion blocked (rapid data-loss prevention): only the repo owner deletes a repo, by name, "
                 "by hand. Offending: %s" % " ".join(w.raw for w in words))
        return

    if name == "git":
        check_git(args, env, envprefix, ctx, words)


RELEASE_MSG = ("rapid release blocked (rapid guard): main is production and promotion to main is the owner's decision; "
               "an agent never releases. Report that dev is ready (rapid release --dry-run shows what would ship). "
               "Offending: %s")


RELEASE_TAG_MSG = ("release tag blocked (rapid guard): main is production and a release/<version> tag is the owner's "
                   "release, made only by the owner's rapid release; an agent never creates, writes or pushes one. "
                   "Report that dev is ready (rapid release --dry-run). Offending: %s")


def _rapid_release(args):
    """True when rapid's arguments are a real release: the verb release without --dry-run."""
    texts = [w.text for w in args]
    if not texts or texts[0] != "release":
        return False
    if any(w.dynamic for w in args[1:]):
        return True
    return "--dry-run" not in texts[1:]


# the first line of rapid, as it reads now and as older pinned versions read
RAPID_MARKS = (b"# rapid - software development lifecycle tool",)


def _is_rapid_program(word, ctx, env):
    """True when WORD runs rapid: named rapid or .rapid/rapid, or a file (found by path or on PATH, links
    followed) whose content is rapid's or whose directory holds lib/policy.sh (audit 4 H5: a renamed copy
    or a link to rapid is still rapid)."""
    t = word.text
    if os.path.basename(t) == "rapid" or t.endswith(".rapid/rapid"):
        return True
    if word.dynamic:
        return False
    if "/" in t:
        p = expand(word, ctx.cwd, env)
    else:
        p = None
        for d in env.get("PATH", os.environ.get("PATH", "")).split(":"):
            c = os.path.join(d or ".", t)
            if os.path.isfile(c) and os.access(c, os.X_OK):
                p = c
                break
    if not p:
        return False
    try:
        r = os.path.realpath(p)
        if not os.path.isfile(r):
            return False
        if os.path.isfile(os.path.join(os.path.dirname(r), "lib", "policy.sh")):
            return True
        with open(r, "rb") as f:
            head = f.read(4096)
            return any(m in head for m in RAPID_MARKS)
    except OSError:
        return False


def _same_file(a, b):
    try:
        if os.path.realpath(a) == os.path.realpath(b):
            return True
        with open(a, "rb") as fa, open(b, "rb") as fb:
            return fa.read() == fb.read()
    except OSError:
        return False


def _check_clobber(targets, ctx, env, what):
    """An existing file outside the temp roots whose content would be destroyed in place."""
    for w in targets:
        p = expand(w, ctx.cwd, env)
        if p is None:
            deny("%s on a path given by a run-time value blocked (rapid guard). Offending: %s" % (what, ctx.raw))
        if p.startswith("/dev/") or is_tmp(p, narrowed=False):
            continue
        if os.path.isfile(p) and os.path.getsize(p) > 0:
            deny("%s would destroy the content of %s in place (rapid guard): move it to the Trash first, or write a "
                 "new file. Offending: %s" % (what, p, ctx.raw))


def check_truncating_redirs(redirs, ctx, env):
    """: > file and a bare > file empty an existing file (round 2 L3); called only for an empty
    command or the no-op builtins, never for a command that writes output."""
    _check_clobber([t for op, t in redirs if op in (">", ">|", "&>") and t is not None and not t.text.startswith("&")],
                   ctx, env, "emptying redirect")


def _check_tmux(args, ctx, depth):
    """tmux runs a shell command for new sessions, windows, panes, run-shell, if-shell and
    send-keys types into a shell (round 2 M5): every such argument is read as a script."""
    if not args:
        return
    sub = args[0].text
    runs = {"new", "new-session", "new-window", "neww", "split-window", "splitw", "respawn-pane", "respawnp",
            "respawn-window", "respawnw", "run-shell", "run", "if-shell", "if", "display-popup", "popup",
            "send-keys", "send", "pipe-pane", "pipep"}
    if sub not in runs:
        return
    value_flags = {"-s", "-n", "-c", "-t", "-x", "-y", "-e", "-F", "-l", "-p", "-T", "-w", "-h", "-d", "-b", "-N", "-K",
                   "-X", "-R", "-M", "-H", "-E"}
    takes = {"-s", "-n", "-c", "-t", "-x", "-y", "-e", "-F", "-l", "-p", "-T", "-w", "-h", "-N"}
    rest, i = args[1:], 0
    text = []
    while i < len(rest):
        t = rest[i].text
        if t.startswith("-") and t in value_flags | takes:
            i += 2 if t in takes else 1
            continue
        if rest[i].dynamic:
            deny("tmux %s with a run-time command blocked (rapid guard). Offending: %s" % (sub, ctx.raw))
        text.append(t)
        i += 1
    if sub in ("send-keys", "send"):
        text = [t for t in text if not re.fullmatch(r"(C|M|S)-.|Enter|KPEnter|Escape|Tab|Space|BSpace|Up|Down|Left|Right", t)]
        if text:
            parse_script(" ".join(text), Ctx(None, ctx.raw), depth + 1)
        return
    for t in text:
        parse_script(t, Ctx(ctx.cwd, ctx.raw), depth + 1)


def check_deletion(targets, ctx, env, envprefix, xargs, words):
    raw = " ".join(w.raw for w in words)
    msg = ("Deletion blocked (rapid data-loss prevention): move it to the Trash (macOS: '/usr/bin/trash <path>', "
           "Linux: 'gio trash <path>') so it stays recoverable. Only absolute paths under /tmp, /private/tmp or "
           "$TMPDIR may be rm'd, never through xargs, -exec or an env prefix. Offending: %s" % raw)
    if envprefix or xargs or not targets:
        deny(msg)
    for w in targets:
        p = expand(w, ctx.cwd, env)
        if p is None or not is_tmp(p, narrowed=False):
            deny(msg)

