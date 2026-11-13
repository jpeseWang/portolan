#!/usr/bin/env bash
# sdw bootstrap: the user-level pieces a plugin cannot ship. Exit codes: docs/internals.md §3.17.
set -u

here=$(cd "$(dirname "$0")" && pwd -P)
MARKET=sdw-local
PLUGIN=sdw@sdw-local
PW_CLI_VERSION=0.1.22
AXE_VERSION=4.10.3
REL="$HOME/.local/share/sdw/release"
CDIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SETTINGS="$CDIR/settings.json"
RECORD="$CDIR/sdw-bootstrap.json"
VSKILL="$CDIR/skills/verify"
VMARK='<!-- sdw-verify-skill -->'
SSKILL="$CDIR/skills/security-audit"
SEC_REPO=${SDW_SECURITY_SKILL_REPO:-https://github.com/cloudflare/security-audit-skill}
SEC_REF=${SDW_SECURITY_SKILL_REF:-c1c8a8c1471069fb0e188eeaff69b8e8db6564a8}
V1_MARKER='solo-dev-workflow:generated'
V1_EXCLUDE='# Solo Dev Workflow — never commit these'
V1_AGENTS='# Dev Workflow — Agent Guide'
TS=$(date +%Y%m%d-%H%M%S)

usage() {
  cat <<'EOF'
usage: bootstrap.sh [--with-qa-tools] [--verify-skill] [--security-skill] [--agents-md] [--dry-run]
       bootstrap.sh --update [--with-qa-tools] [--verify-skill] [--security-skill] [--dry-run]
       bootstrap.sh --uninstall [--dry-run]
       bootstrap.sh --migrate <project-dir> [--dry-run]

Install (default): release clone at ~/.local/share/sdw/release on the newest vX.Y.Z tag,
  register it as marketplace sdw-local, install sdw@sdw-local at user scope, merge
  templates/user-settings.json into ~/.claude/settings.json (diff + backup; added keys
  recorded in ~/.claude/sdw-bootstrap.json), create ~/.claude/CLAUDE.md only if missing.
  --with-qa-tools   npm -g @playwright/cli (pinned), its Chromium, axe-core in ~/.cache/sdw/axe
  --verify-skill    install ~/.claude/skills/verify (gate + tamper check before commits)
  --security-skill  install Cloudflare's security-audit skill at a pinned commit in
                    ~/.claude/skills/security-audit
  --agents-md       print the opt-in that loads AGENTS.md beside CLAUDE.md (not applied)
  CLAUDE_CONFIG_DIR set: settings, record and skills go there instead of ~/.claude; CLAUDE.md
  is not created there (Claude Code still loads ~/.claude/CLAUDE.md).
--update     fetch tags, check out the newest, refresh settings and the installed skills
--uninstall  remove the plugin, the marketplace, the release clone and recorded settings
--migrate    clean a v1 (install.sh) project: generated files, hook wiring, CLAUDE.md
--dry-run    print every action, change nothing
Exit: 0 ok, 1 a step failed, 2 usage, 4 claude/git/jq missing.
EOF
}

die_usage() { printf 'sdw: %s\n' "$1" >&2; usage >&2; exit 2; }

MODE=install DRY=0 QA=0 AGENTS=0 VERIFY=0 SEC=0 MDIR="" FAILED=0
set_mode() { [ "$MODE" = install ] || die_usage "only one of --update, --uninstall, --migrate"; MODE=$1; }
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --dry-run) DRY=1 ;;
    --with-qa-tools) QA=1 ;;
    --verify-skill) VERIFY=1 ;;
    --security-skill) SEC=1 ;;
    --agents-md) AGENTS=1 ;;
    --update) set_mode update ;;
    --uninstall) set_mode uninstall ;;
    --migrate) set_mode migrate; [ $# -ge 2 ] || die_usage "--migrate needs a directory"; MDIR=$2; shift ;;
    *) die_usage "unknown argument: $1" ;;
  esac
  shift
done
case "$MODE" in
  uninstall|migrate) [ "$QA$VERIFY$SEC$AGENTS" = 0000 ] || die_usage "--with-qa-tools, --verify-skill, --security-skill, --agents-md go with install or --update" ;;
  update) [ "$AGENTS" = 0 ] || die_usage "--agents-md goes with install" ;;
esac

say() { printf 'sdw: %s\n' "$*"; }
warn() { printf 'sdw: warning: %s\n' "$*" >&2; }
fail() { printf 'sdw: FAILED: %s\n' "$*" >&2; FAILED=1; }
q() {
  local out="" a
  for a in "$@"; do
    case "$a" in
      ""|*[!A-Za-z0-9_./:@=+%,-]*) a="'$(printf '%s' "$a" | sed "s/'/'\\\\''/g")'" ;;
    esac
    out="$out${out:+ }$a"
  done
  printf '%s' "$out"
}
act() { if [ "$DRY" = 1 ]; then printf '  (dry-run) %s\n' "$*"; else printf '  %s\n' "$*"; fi; }
run() { act "\$ $(q "$@")"; [ "$DRY" = 1 ] || "$@"; }
run_in() { local d=$1; shift; act "\$ (cd $(q "$d") && $(q "$@"))"; [ "$DRY" = 1 ] || (cd "$d" && "$@"); }
do_mkdir() { [ -d "$1" ] && return 0; act "mkdir $(q "$1")"; [ "$DRY" = 1 ] || mkdir -p "$1"; }
do_rm() { act "remove $(q "$1")"; [ "$DRY" = 1 ] || rm -f -- "$1"; }
do_rmdir_tree() { act "remove dir $(q "$1")"; [ "$DRY" = 1 ] || rm -rf -- "$1"; }
do_mv() { act "move $(q "$1") -> $(q "$2")"; [ "$DRY" = 1 ] || mv -f -- "$1" "$2"; }
do_cp() { act "copy $(q "$1") -> $(q "$2")"; [ "$DRY" = 1 ] || cp -p -- "$1" "$2"; }
# A symlinked destination (dotfiles) is written through, so the link survives.
do_write() {
  local dst=$2
  if [ -L "$dst" ]; then
    local t n=0
    while [ -L "$dst" ] && [ $n -lt 20 ]; do
      t=$(readlink "$dst"); case "$t" in /*) dst=$t ;; *) dst="$(dirname "$dst")/$t" ;; esac; n=$((n + 1))
    done
    [ -L "$dst" ] && { fail "symlink loop at $2"; return 1; }
    act "write $(q "$dst") (via symlink $(q "$2"))"
  else
    act "write $(q "$dst")"
  fi
  [ "$DRY" = 1 ] || { cat "$1" > "$dst.sdw-tmp" && mv -f -- "$dst.sdw-tmp" "$dst"; }
}

need() {
  local t
  for t in "$@"; do
    command -v "$t" >/dev/null 2>&1 || { printf 'sdw: %s not found on PATH\n' "$t" >&2; exit 4; }
  done
}
case "$MODE" in
  install|update) need git jq claude ;;
  uninstall) need jq claude ;;
  migrate) need git jq ;;
esac

WORK=$(mktemp -d "${TMPDIR:-/tmp}/sdw-bootstrap.XXXXXX") || exit 1
trap 'rm -rf "$WORK"' EXIT

phys() { (cd "$1" 2>/dev/null && pwd -P); }
tpl() { if [ -f "$REL/templates/$1" ]; then printf '%s' "$REL/templates/$1"; else printf '%s' "$here/templates/$1"; fi; }
cks() { cksum < "$1" | awk '{print $1 "-" $2}'; }

newest_tag() {
  (cd "$1" && git tag -l 'v[0-9]*') |
    awk -F. '/^v[0-9]+\.[0-9]+\.[0-9]+$/ { printf "%d %d %d %s\n", substr($1, 2), $2, $3, $0 }' |
    sort -n -k1,1 -k2,2 -k3,3 | tail -1 | awk '{print $4}'
}

# ---------- record (~/.claude/sdw-bootstrap.json) ----------
rec_get() { [ -f "$RECORD" ] && jq -c "$1" "$RECORD" 2>/dev/null || printf 'null\n'; }
rec_update() {
  local base="$WORK/rec.in" f
  if [ -f "$RECORD" ]; then cp "$RECORD" "$base"; else printf '{"v":1}\n' > "$base"; fi
  f="$WORK/rec.out"
  jq "$@" "$base" > "$f" || { fail "cannot update $RECORD"; return 1; }
  cmp -s "$f" "$base" && [ -f "$RECORD" ] && return 0
  do_mkdir "$CDIR"
  do_write "$f" "$RECORD"
}

# ---------- release clone ----------
ensure_release() {
  local src=$here tag cur
  if [ -e "$REL/.git" ]; then
    say "release clone: $REL"
    if [ -n "$(cd "$REL" && git status --porcelain)" ]; then
      fail "$REL has local changes; it must stay a clean tag checkout"
      return 1
    fi
    [ "$MODE" = update ] && { run_in "$REL" git fetch -q --tags origin || { fail "git fetch in $REL"; return 1; }; }
    tag=$(newest_tag "$REL")
  elif [ -e "$REL" ]; then
    fail "$REL exists but is not a git clone; move it away"
    return 1
  else
    say "release clone: $REL (new, from $src)"
    do_mkdir "$(dirname "$REL")"
    run git clone -q "$src" "$REL" || { fail "git clone $src"; return 1; }
    if [ "$DRY" = 1 ]; then tag=$(newest_tag "$src"); else tag=$(newest_tag "$REL"); fi
  fi
  [ -n "$tag" ] || { fail "no vX.Y.Z tag in $src; cut one with: git tag v2.0.0"; return 1; }
  cur=""
  [ -e "$REL/.git" ] && cur=$(cd "$REL" && git rev-parse -q --verify HEAD 2>/dev/null)
  if [ -n "$cur" ] && [ "$cur" = "$(cd "$REL" && git rev-parse -q --verify "$tag^{commit}" 2>/dev/null)" ]; then
    say "release clone is at $tag"
  else
    run_in "$REL" git -c advice.detachedHead=false checkout -q "$tag" || { fail "checkout $tag"; return 1; }
    say "release clone now at $tag"
  fi
  [ "$MODE" = update ] || rec_update --arg d "$REL" '.release_dir = $d'
}

# ---------- plugin ----------
ensure_plugin() {
  local mpath n
  mpath=$(claude plugin marketplace list --json 2>/dev/null |
    jq -r --arg n "$MARKET" '.[]? | select(.name == $n) | (.path // .installLocation // "")' 2>/dev/null | head -1)
  if [ -n "$mpath" ] && [ "$(phys "$mpath")" = "$(phys "$REL")" ]; then
    say "marketplace $MARKET already points at the release clone"
  else
    [ -n "$mpath" ] && say "marketplace $MARKET points at $mpath; repointing it at the release clone"
    run claude plugin marketplace add "$REL" --scope user || { fail "claude plugin marketplace add"; return 1; }
  fi
  n=$(claude plugin list --json 2>/dev/null |
    jq -r --arg id "$PLUGIN" '[.[]? | select(.id == $id and .scope == "user")] | length' 2>/dev/null)
  if [ "${n:-0}" -gt 0 ] 2>/dev/null; then
    say "plugin $PLUGIN already installed (user scope)"
  else
    run claude plugin install "$PLUGIN" --scope user || { fail "claude plugin install $PLUGIN"; return 1; }
  fi
}

# ---------- settings merge ----------
JQ_LIB='
def present($p): (try getpath($p[:-1]) catch null) as $o | (($o | type) == "object" and ($o | has($p[-1])));
def leaves: . as $t | [paths(type != "object")] | map(select(all(.[]; type == "string"))) | .[] as $p
  | ($t | getpath($p)) as $v
  | if ($v | type) == "array" then ($v[] | {path: $p, item: .}) else {path: $p, value: $v} end;
def missing($s; $p; $n): [range(1; $n + 1) as $i | $p[:$i] as $pre | select(($s | try getpath($pre) catch 0) == null) | $pre];
def merge($u; $t):
  reduce ($t | leaves) as $l ({s: $u, added: [], created: [], kept: []};
    . as $acc | $l.path as $p
    | ($acc.s | try getpath($p) catch {"__sdw_conflict": true}) as $cur
    | if ($cur | type) == "object" and ($cur | has("__sdw_conflict")) then .kept += [{path: $p, why: "conflicting type"}]
      elif ($l | has("item")) then
        if $cur == null then .created += missing($acc.s; $p; ($p | length)) | .s |= setpath($p; [$l.item]) | .added += [$l]
        elif ($cur | type) != "array" then .kept += [{path: $p, why: "not a list"}]
        elif any($cur[]; . == $l.item) then .
        else .s |= setpath($p; $cur + [$l.item]) | .added += [$l] end
      elif ($acc.s | present($p)) | not then
        .created += missing($acc.s; $p; ($p | length) - 1) | .s |= setpath($p; $l.value) | .added += [$l]
      elif $cur == $l.value then .
      else .kept += [{path: $p, why: "yours kept", yours: $cur, template: $l.value}] end);
def unmerge($added; $created):
  reduce $added[] as $a ({s: ., removed: 0, kept: []};
    $a.path as $p | (.s | try getpath($p) catch null) as $cur
    | if ($a | has("item")) then
        if ($cur | type) == "array" and any($cur[]; . == $a.item)
        then .s |= setpath($p; [$cur[] | select(. != $a.item)]) | .removed += 1 else . end
      elif (.s | present($p)) | not then .
      elif $cur == $a.value then .s |= delpaths([$p]) | .removed += 1
      else .kept += [{path: $p, why: "changed since install", yours: $cur}] end)
  | reduce ($created | sort_by(length) | reverse)[] as $c (.;
      (.s | try getpath($c) catch null) as $v
      | if $v == {} or $v == [] then .s |= delpaths([$c]) else . end);
'

current_settings() { # copy settings.json (or {}) to $1; fail when it is not JSON
  if [ -f "$SETTINGS" ] && [ -s "$SETTINGS" ]; then
    jq . "$SETTINGS" > "$1" 2>/dev/null || { fail "$SETTINGS is not valid JSON; fix it, then re-run"; return 1; }
  else
    printf '{}\n' > "$1"
  fi
}

show_kept() {
  jq -r '.kept[] | "  note: \(.path | join(".")): \(.why)" + (if has("yours") then " (yours: \(.yours | tojson))" else "" end)' "$1"
}

apply_settings() { # apply_settings <new-settings-file> <old-settings-file>
  say "settings diff ($SETTINGS):"
  diff -u "$2" "$1" | sed '1,2d; s/^/    /'
  if [ -f "$SETTINGS" ]; then do_cp "$SETTINGS" "$SETTINGS.sdw-backup-$TS"; fi
  do_mkdir "$CDIR"
  do_write "$1" "$SETTINGS"
}

merge_settings() {
  local t old="$WORK/settings.old" res="$WORK/merge.json" new="$WORK/settings.new" n
  t=$(tpl user-settings.json)
  [ -f "$t" ] || { fail "missing template $t"; return 1; }
  current_settings "$old" || return 1
  jq -n --slurpfile u "$old" --slurpfile t "$t" "$JQ_LIB"' merge($u[0] // {}; $t[0])' > "$res" ||
    { fail "settings merge"; return 1; }
  show_kept "$res"
  n=$(jq '.added | length' "$res")
  if [ "$n" = 0 ]; then
    say "settings: nothing to add; every template entry is present"
    return 0
  fi
  jq '.s' "$res" > "$new"
  say "settings: adding $n entries"
  apply_settings "$new" "$old"
  rec_update --slurpfile r "$res" \
    '.settings_added = (((.settings_added // []) + $r[0].added) | unique)
     | .settings_created = (((.settings_created // []) + $r[0].created) | unique)'
}

unmerge_settings() {
  local old="$WORK/settings.old" res="$WORK/unmerge.json" new="$WORK/settings.new"
  if [ "$(rec_get '.settings_added | length')" = null ] || [ "$(rec_get '.settings_added | length')" = 0 ]; then
    say "settings: nothing recorded, left alone"
    return 0
  fi
  [ -f "$SETTINGS" ] || { say "settings: $SETTINGS is gone, nothing to remove"; return 0; }
  current_settings "$old" || return 1
  jq --slurpfile r "$RECORD" "$JQ_LIB"' unmerge($r[0].settings_added // []; $r[0].settings_created // [])' "$old" > "$res" ||
    { fail "settings unmerge"; return 1; }
  show_kept "$res"
  jq '.s' "$res" > "$new"
  if cmp -s "$new" "$old"; then
    say "settings: recorded entries already gone"
    return 0
  fi
  say "settings: removing $(jq '.removed' "$res") recorded entries"
  apply_settings "$new" "$old"
}

# ---------- user files ----------
ensure_claude_md() {
  local t
  t=$(tpl global-memory.md)
  if [ "$CDIR" != "$HOME/.claude" ]; then
    say "CLAUDE_CONFIG_DIR=$CDIR: memory stays in ~/.claude/CLAUDE.md, which Claude Code still loads"
    return 0
  fi
  if [ -e "$CDIR/CLAUDE.md" ]; then
    say "$CDIR/CLAUDE.md exists, left alone (template: $t)"
    return 0
  fi
  do_mkdir "$CDIR"
  do_cp "$t" "$CDIR/CLAUDE.md" || { fail "write ~/.claude/CLAUDE.md"; return 1; }
  [ "$DRY" = 1 ] && return 0
  rec_update --arg c "$(cks "$CDIR/CLAUDE.md")" '.claude_md_cksum = $c'
}

ensure_verify_skill() {
  local t f n=0
  t=$(dirname "$(tpl verify-skill/SKILL.md)")
  [ -f "$t/SKILL.md" ] || { fail "missing template $t/SKILL.md"; return 1; }
  if [ -e "$VSKILL" ] && ! grep -qF "$VMARK" "$VSKILL/SKILL.md" 2>/dev/null; then
    say "skip: $VSKILL exists and is not the sdw one"
    return 0
  fi
  for f in "$t"/*; do
    [ -f "$f" ] || continue
    cmp -s "$f" "$VSKILL/${f##*/}" && continue
    do_mkdir "$VSKILL"
    do_cp "$f" "$VSKILL/${f##*/}" || { fail "install verify skill"; return 1; }
    n=$((n + 1))
  done
  [ "$n" = 0 ] && say "verify skill is current ($VSKILL)"
  rec_update '.verify_skill = true'
}

# Third-party skill: copied unmodified from a reviewed commit; bump SEC_REF only after reading the diff.
security_skill() {
  local have src="$WORK/security-audit-skill" f
  have=$(rec_get '.security_skill' | tr -d '"')
  if [ -e "$SSKILL" ] && [ "$have" = null ]; then
    say "skip: $SSKILL exists and is not the sdw one (remove it, e.g. npx skills remove -g security-audit, then rerun)"
    return 0
  fi
  if [ "$have" = "$SEC_REF" ] && [ -f "$SSKILL/SKILL.md" ]; then
    say "security-audit skill is current ($SSKILL @ $(printf '%.7s' "$SEC_REF"))"
    return 0
  fi
  run git clone -q "$SEC_REPO" "$src" || { fail "git clone $SEC_REPO"; return 1; }
  run git -C "$src" checkout -q "$SEC_REF" || { fail "security-audit skill: no commit $SEC_REF"; return 1; }
  if [ "$DRY" = 1 ]; then
    act "copy skills/security-audit/ and LICENSE -> $(q "$SSKILL")"
  else
    [ -f "$src/skills/security-audit/SKILL.md" ] || { fail "security-audit skill: no skills/security-audit/SKILL.md at $SEC_REF"; return 1; }
    [ -e "$SSKILL" ] && do_rmdir_tree "$SSKILL"
    do_mkdir "$SSKILL"
    for f in "$src/skills/security-audit"/* "$src/LICENSE"; do
      [ -f "$f" ] || continue
      do_cp "$f" "$SSKILL/${f##*/}" || { fail "install security-audit skill"; return 1; }
    done
  fi
  rec_update --arg r "$SEC_REF" '.security_skill = $r'
}

qa_tools() {
  if ! command -v npm >/dev/null 2>&1; then
    fail "--with-qa-tools needs npm (Node >= 18) on PATH"
    return 1
  fi
  if command -v playwright-cli >/dev/null 2>&1 &&
     [ "$(playwright-cli --version 2>/dev/null | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -1)" = "$PW_CLI_VERSION" ]; then
    say "playwright-cli $PW_CLI_VERSION already installed"
  else
    run npm install -g "@playwright/cli@$PW_CLI_VERSION" || { fail "npm install -g @playwright/cli"; return 1; }
  fi
  run playwright-cli install-browser chromium || { fail "playwright-cli install-browser chromium"; return 1; }
  axe_dir="${SDW_CACHE_DIR:-$HOME/.cache/sdw}/axe"
  if [ -f "$axe_dir/node_modules/axe-core/axe.min.js" ]; then
    say "axe-core cache present ($axe_dir)"
  else
    run npm install --prefix "$axe_dir" --no-audit --no-fund "axe-core@$AXE_VERSION" || { fail "npm install axe-core"; return 1; }
  fi
  say "not installed on purpose: the playwright-cli global skill (sdw:qa carries its own notes)"
  command -v uv >/dev/null 2>&1 || say "for /sdw:qa --api-fuzz (Schemathesis): brew install uv"
}

agents_md() {
  say "AGENTS.md beside CLAUDE.md (unverified on this Claude Code version; not applied):"
  printf '    %s\n' "printf '{\"instructionFiles\":\"claude-md-and-agents-md\"}' | claude plugin configure cc-plugin-agents-md@builtin --values-stdin"
  say "check with: claude plugin configure cc-plugin-agents-md@builtin"
}

# ---------- modes ----------
do_install() {
  ensure_release || return 1
  ensure_plugin
  merge_settings
  ensure_claude_md
  [ "$VERIFY" = 1 ] && ensure_verify_skill
  [ "$SEC" = 1 ] && security_skill
  [ "$QA" = 1 ] && qa_tools
  [ "$AGENTS" = 1 ] && agents_md
  say "next: open Claude Code in a client repo or workspace folder and type /sdw:onboard"
}

do_update() {
  ensure_release || return 1
  ensure_plugin
  merge_settings
  if [ "$VERIFY" = 1 ] || [ "$(rec_get '.verify_skill')" = true ]; then ensure_verify_skill; fi
  if [ "$SEC" = 1 ] || [ "$(rec_get '.security_skill')" != null ]; then security_skill; fi
  [ "$QA" = 1 ] && qa_tools
  say "run /reload-plugins in open sessions"
}

do_uninstall() {
  local n c
  n=$(claude plugin list --json 2>/dev/null |
    jq -r --arg id "$PLUGIN" '[.[]? | select(.id == $id and .scope == "user")] | length' 2>/dev/null)
  if [ "${n:-0}" -gt 0 ] 2>/dev/null; then
    run claude plugin uninstall "$PLUGIN" --scope user || fail "claude plugin uninstall"
  else
    say "plugin $PLUGIN not installed"
  fi
  if claude plugin marketplace list --json 2>/dev/null | jq -e --arg n "$MARKET" 'any(.[]?; .name == $n)' >/dev/null 2>&1; then
    run claude plugin marketplace remove "$MARKET" || fail "claude plugin marketplace remove"
  else
    say "marketplace $MARKET not registered"
  fi
  unmerge_settings
  if [ -f "$VSKILL/SKILL.md" ] && grep -qF "$VMARK" "$VSKILL/SKILL.md"; then
    do_rmdir_tree "$VSKILL"
  fi
  if [ "$(rec_get '.security_skill')" != null ] && [ -d "$SSKILL" ]; then do_rmdir_tree "$SSKILL"; fi
  c=$(rec_get '.claude_md_cksum' | tr -d '"')
  if [ -f "$CDIR/CLAUDE.md" ] && [ "$c" != null ]; then
    if [ "$(cks "$CDIR/CLAUDE.md")" = "$c" ]; then do_rm "$CDIR/CLAUDE.md"
    else say "$CDIR/CLAUDE.md edited since install, left alone"; fi
  fi
  if [ -e "$REL/.git" ]; then do_rmdir_tree "$REL"; fi
  if [ -f "$RECORD" ]; then
    if [ "$FAILED" = 0 ]; then do_rm "$RECORD"; else say "kept $RECORD for a retry"; fi
  fi
  say "left in place: per-project .sdw/ (run /sdw:offboard first), ~/.cache/sdw, Keychain items sdw:*"
  command -v playwright-cli >/dev/null 2>&1 && say "playwright-cli stays installed; remove with: npm rm -g @playwright/cli"
  return 0
}

# ---------- migrate (v1 install.sh projects) ----------
M_GIT=0
tracked() { [ "$M_GIT" = 1 ] && (cd "$D" && git ls-files --error-unmatch -- "$1" >/dev/null 2>&1); }
modified() { (cd "$D" && ! git diff --quiet -- "$1"); }
backup() { # backup <relpath>: copy under the backup dir, never inside the project
  do_mkdir "$(dirname "$BK/$1")"
  act "backup $(q "$D/$1") -> $(q "$BK/$1")"
  [ "$DRY" = 1 ] || cp -pP -- "$D/$1" "$BK/$1"
}
v1_header() { # v1_header <name> <line2>: true when a legacy hook/tool file matches by name and header
  case "$1|$2" in
    "format-file.sh|# PostToolUse hook for Edit / Write"*) return 0 ;;
    "guard-bash.sh|# PreToolUse hook for Bash"*) return 0 ;;
    "guard-write.sh|# PreToolUse hook for Edit / Write / NotebookEdit"*) return 0 ;;
    "session-start.sh|# SessionStart hook"*) return 0 ;;
    "statusline.sh|# statusLine hook"*) return 0 ;;
    "stop-gate.sh|# Stop hook"*) return 0 ;;
    "cfg.sh|# Read one value from config.env"*) return 0 ;;
    'docs-freshness.py|"""How much of the local docs'*) return 0 ;;
    'toolchain-check.py|"""Does the toolchain on PATH'*) return 0 ;;
    'ui-diff.py|"""Compare a design export with a screenshot'*) return 0 ;;
    "ui-shot.mjs|// Capture one route the way a reviewer"*) return 0 ;;
  esac
  return 1
}
is_v1_agents() { [ -f "$D/AGENTS.md" ] && [ ! -L "$D/AGENTS.md" ] && [ "$(head -1 "$D/AGENTS.md")" = "$V1_AGENTS" ]; }

m_generated() {
  local d f rel removed=0 kept=0
  say "step 1: v1-generated files"
  for d in .claude/commands .claude/skills .claude/agents .github/prompts .agents/workflows \
           .agent/workflows .windsurf/workflows .cursor/commands .codex/prompts; do
    [ -d "$D/$d" ] || continue
    while IFS= read -r -d '' f; do
      rel=${f#"$D"/}
      if grep -qF "$V1_MARKER" "$f" 2>/dev/null; then
        if tracked "$rel"; then say "  tracked, left (remove in a PR if wanted): $rel"; kept=$((kept + 1))
        else do_rm "$f"; removed=$((removed + 1)); fi
      else
        say "  not generated by v1, kept: $rel"; kept=$((kept + 1))
      fi
    done < <(find "$D/$d" -type f -print0)
  done
  for d in .claude/hooks .claude/tools; do
    [ -d "$D/$d" ] || continue
    while IFS= read -r -d '' f; do
      rel=${f#"$D"/}
      if v1_header "$(basename "$f")" "$(sed -n 2p "$f")" && ! tracked "$rel"; then
        do_rm "$f"; removed=$((removed + 1))
      else
        say "  kept: $rel"; kept=$((kept + 1))
      fi
    done < <(find "$D/$d" -maxdepth 1 -type f -print0)
  done
  for f in .github/copilot-instructions.md .windsurf/rules/agents.md .zed/AGENT.md; do
    if [ -L "$D/$f" ] && ! tracked "$f"; then
      case "$(readlink "$D/$f")" in */AGENTS.md|AGENTS.md) do_rm "$D/$f"; removed=$((removed + 1)) ;; esac
    fi
  done
  if [ "$DRY" = 0 ]; then
    for d in .claude/commands .claude/skills .claude/agents .claude/hooks .claude/tools .github/prompts \
             .agents .agent .windsurf .cursor .codex .zed; do
      [ -d "$D/$d" ] && find "$D/$d" -depth -type d -empty -exec rmdir {} \; 2>/dev/null
    done
  fi
  say "  $removed removed, $kept left alone"
}

M_LEGACY='def legacy: (.command // "") | contains(".claude/hooks/");'
m_settings() {
  local f="$D/.claude/settings.json" n new="$WORK/msettings.json"
  say "step 2: legacy hook wiring in .claude/settings.json"
  [ -f "$f" ] || { say "  none"; return 0; }
  n=$(jq "$M_LEGACY"' ([(.hooks // {})[]?[]?.hooks[]? | select(legacy)] | length)
        + (if (.statusLine | type) == "object" and (.statusLine | legacy) then 1 else 0 end)
        + ([.permissions.allow[]? | select(type == "string" and contains(".claude/tools/"))] | length)' "$f" 2>/dev/null) ||
    { fail ".claude/settings.json is not valid JSON"; return 1; }
  [ "$n" = 0 ] && { say "  no legacy entries"; return 0; }
  if tracked .claude/settings.json; then
    say "  tracked by the repo; remove these $n entries by hand (or in a PR):"
    jq "$M_LEGACY"' {hooks: [(.hooks // {}) | to_entries[] | {event: .key, commands: [.value[]?.hooks[]? | select(legacy) | .command]} | select(.commands | length > 0)],
        statusLine: (if (.statusLine | type) == "object" and (.statusLine | legacy) then .statusLine.command else null end),
        allow: [.permissions.allow[]? | select(type == "string" and contains(".claude/tools/"))]}' "$f" | sed 's/^/    /'
    return 0
  fi
  jq "$M_LEGACY"' (if (.statusLine | type) == "object" and (.statusLine | legacy) then del(.statusLine) else . end)
      | if (.hooks | type) == "object" then
          .hooks |= (with_entries(.value |= [.[]? | (.hooks |= [.[]? | select(legacy | not)]) | select((.hooks | length) > 0)])
                     | with_entries(select((.value | length) > 0)))
          | if .hooks == {} then del(.hooks) else . end
        else . end
      | if (.permissions.allow | type) == "array"
        then .permissions.allow |= [.[] | select((type == "string" and contains(".claude/tools/")) | not)] else . end' "$f" > "$new" ||
    { fail "cleaning .claude/settings.json"; return 1; }
  backup .claude/settings.json
  diff -u "$f" "$new" | sed '1,2d; s/^/    /'
  do_write "$new" "$f"
}

m_instructions() {
  local v1a=0 tgt
  say "step 3: CLAUDE.md / AGENTS.md"
  is_v1_agents && ! tracked AGENTS.md && v1a=1
  if [ -L "$D/CLAUDE.md" ]; then
    tgt=$(readlink "$D/CLAUDE.md")
    if tracked CLAUDE.md; then
      if modified CLAUDE.md; then
        run_in "$D" git checkout -- CLAUDE.md || fail "git checkout -- CLAUDE.md"
        if [ "$DRY" = 0 ] && [ -f "$D/CLAUDE.md.bak" ] && ! tracked CLAUDE.md.bak && cmp -s "$D/CLAUDE.md" "$D/CLAUDE.md.bak"; then
          do_rm "$D/CLAUDE.md.bak"
        fi
      else
        say "  CLAUDE.md is the repo's own tracked symlink, left alone"
      fi
    elif [ -f "$D/CLAUDE.md.bak" ] && [ ! -L "$D/CLAUDE.md.bak" ]; then
      do_rm "$D/CLAUDE.md"
      do_mv "$D/CLAUDE.md.bak" "$D/CLAUDE.md"
    elif [ "$v1a" = 1 ] && [ "$(basename "$tgt")" = AGENTS.md ]; then
      do_rm "$D/CLAUDE.md"
    else
      say "  CLAUDE.md -> $tgt: a link to the team's AGENTS.md is read once; safe to leave"
    fi
  else
    say "  CLAUDE.md is not a symlink, left alone"
  fi
  if is_v1_agents; then
    if tracked AGENTS.md; then
      if modified AGENTS.md; then
        backup AGENTS.md
        run_in "$D" git checkout -- AGENTS.md || fail "git checkout -- AGENTS.md"
      else
        say "  the repo commits the v1 AGENTS.md itself; left alone"
      fi
    else
      backup AGENTS.md
      if [ -f "$D/AGENTS.md.bak" ] && [ ! -L "$D/AGENTS.md.bak" ]; then do_mv "$D/AGENTS.md.bak" "$D/AGENTS.md"
      else do_rm "$D/AGENTS.md"; fi
    fi
  fi
}

m_exclude() {
  local repos="" r ex bin f hidden
  say "step 4: .git/info/exclude"
  if [ "$M_GIT" = 1 ]; then
    repos=$(cd "$D" && git rev-parse --show-toplevel)
  else
    for r in "$D"/*/.git; do [ -d "$r" ] && repos="$repos${repos:+
}$(dirname "$r")"; done
  fi
  [ -n "$repos" ] || { say "  no git repo here"; return 0; }
  bin="$here/plugin/bin/sdw-exclude"
  [ -x "$bin" ] || bin="$REL/plugin/bin/sdw-exclude"
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    ex="$(cd "$r" && cd "$(git rev-parse --git-common-dir)" && pwd -P)/info/exclude"
    if grep -qxF "$V1_EXCLUDE" "$ex" 2>/dev/null; then
      hidden=""
      for f in config.env .claude/config.env .mcp.json .auth.json; do [ -f "$r/$f" ] && hidden="$hidden $f"; done
      if [ -n "$hidden" ]; then
        fail "deferred for $r: the v1 block hides$hidden; delete (or move out) those files, then re-run --migrate"
      elif [ -x "$bin" ]; then
        run_in "$r" "$bin" --legacy "$r" || fail "sdw-exclude --legacy $r"
        say "  files the v1 block hid now show in git status there; review them"
      else
        fail "sdw-exclude not found (looked in $here/plugin/bin and $REL/plugin/bin)"
      fi
    else
      say "  no v1 block in $ex"
    fi
    if grep -qxF "$V1_EXCLUDE" "$r/.gitignore" 2>/dev/null; then
      say "  $r/.gitignore carries a v1 block; it is the repo's file, edit it by hand if wanted"
    fi
  done <<EOF
$repos
EOF
}

cfg_val() { # cfg_val <file> <KEY>: last value, quotes and trailing / stripped; never used for secrets
  sed -n "s/^[[:space:]]*\(export[[:space:]][[:space:]]*\)\{0,1\}$2=//p" "$1" | tail -1 |
    sed "s/^[\"']//; s/[\"'][[:space:]]*\$//; s:/*\$::"
}
m_secrets() {
  local f base email names
  say "step 5: credentials and project state (printed, not run)"
  for f in "$D/config.env" "$D/.claude/config.env"; do
    [ -f "$f" ] || continue
    names=$(sed -n 's/^[[:space:]]*\(export[[:space:]][[:space:]]*\)\{0,1\}\([A-Z][A-Z0-9_]*\)=.*/\2/p' "$f" |
      grep -E 'TOKEN|SECRET|PASSWORD|PASSWD|APIKEY|CREDENTIAL' | sort -u | tr '\n' ' ')
    [ -n "$names" ] || continue
    say "  $f holds secrets: $names"
    case " $names " in
      *" JIRA_TOKEN "*)
        base=$(cfg_val "$f" JIRA_BASE_URL); email=$(cfg_val "$f" JIRA_EMAIL)
        say "  store the Jira token in Keychain (it prompts for the value):"
        printf '    %s\n' "security add-generic-password -U -s $(q "sdw:jira:${base:-<JIRA_BASE_URL>}") -a $(q "${email:-<JIRA_EMAIL>}") -w"
        ;;
    esac
    say "  then delete $f by hand; secrets live only in Keychain now"
  done
  say "  project context is not migrated: open Claude Code in $D and type /sdw:onboard"
}

m_doctor() {
  local bin="$here/plugin/bin/sdw-doctor"
  say "step 6: sdw-doctor"
  [ -x "$bin" ] || bin="$REL/plugin/bin/sdw-doctor"
  [ -x "$bin" ] || { warn "sdw-doctor not found; skipped"; return 0; }
  run_in "$D" "$bin" || warn "sdw-doctor reported failures (above)"
  return 0
}

do_migrate() {
  [ -d "$MDIR" ] || die_usage "not a directory: $MDIR"
  D=$(phys "$MDIR")
  case "$D" in /|"$(phys "$HOME")") die_usage "refusing to migrate $D" ;; esac
  (cd "$D" && git rev-parse --is-inside-work-tree >/dev/null 2>&1) && M_GIT=1
  BK="$HOME/.local/share/sdw/backups/$(basename "$D")-$TS"
  say "migrating v1 install in $D (backups go to $BK)"
  m_generated
  m_settings
  m_instructions
  m_exclude
  m_secrets
  m_doctor
  local f left=""
  for f in TASKS.md CHANGELOG.md config.env.example .mcp.json.example .github/pull_request_template.md \
           .claude/settings.json.suggested CLAUDE.md.bak AGENTS.md.bak; do
    [ -e "$D/$f" ] && ! tracked "$f" && left="$left $f"
  done
  [ -n "$left" ] && say "v1 left these untracked files (yours to keep or delete):$left"
  return 0
}

[ "$DRY" = 1 ] && say "dry run: nothing will change"
case "$MODE" in
  install) do_install ;;
  update) do_update ;;
  uninstall) do_uninstall ;;
  migrate) do_migrate ;;
esac
[ "$FAILED" = 0 ] || { say "finished with failures (see FAILED lines)"; exit 1; }
say "done"
exit 0
