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

