#!/usr/bin/env bash
# sdw-toolchain, sdw-docs-freshness and sdw-doctor: the v1 bugs stay fixed.
. "$(dirname "$0")/_lib.sh"

R="$tmp/repo"; mkdir -p "$R/api"
: > "$R/.python-version"
expect_rc 0 "empty .python-version does not crash" sdw-toolchain "$R"
printf '{"sdk":{"version":"10.0.100","rollForward":"latestMajor"}}\n' > "$R/api/global.json"
printf '#!/bin/sh\n[ "$1" = --version ] && echo 10.0.400\n' > "$tmp/stub/dotnet"; chmod +x "$tmp/stub/dotnet"
expect_rc 0 "global.json satisfied" sdw-toolchain "$R"
printf '#!/bin/sh\necho "A compatible .NET SDK was not found." >&2; exit 145\n' > "$tmp/stub/dotnet"
expect_rc 1 "global.json unsatisfied" sdw-toolchain "$R" --brief
printf '%s\n' "$OUT" | grep -q 'dotnet wants 10.0.100 (rollForward latestMajor)' || fail "dotnet brief" "$OUT"
[ "$(printf '%s\n' "$OUT" | grep -c .)" -le 3 ] || fail "brief lines" "$OUT"
printf '#!/bin/sh\necho preview\n' > "$tmp/stub/dotnet"
expect_rc 1 "non-numeric dotnet output does not crash" sdw-toolchain "$R"
mkdir -p "$HOME/.dotnet/sdk/10.0.400"
expect_rc 0 "--emit-env finds ~/.dotnet" sh -c "cd \"$R\" && sdw-toolchain --emit-env"
printf '%s\n' "$OUT" | grep -qx 'export DOTNET_ROOT="$HOME/.dotnet"' || fail "emit DOTNET_ROOT" "$OUT"
printf '%s\n' "$OUT" | grep -qx 'export PATH="$HOME/.dotnet:$PATH"' || fail "emit PATH" "$OUT"
printf '%s\n' "$OUT" | grep -v '^#' | grep -v '^export [A-Z_]*="[^"]*"$' && fail "env.sh shape" "$OUT"
ok "emit-env lines are export-only"
rm "$tmp/stub/dotnet"

D="$tmp/docs"; mkdir -p "$D/daily" "$D/sub"
printf '<!-- reviewed: %s | status: current -->\n' "$(date +%Y-%m-%d)" > "$D/STATUS.md"
printf '<!-- fetched: %s | source: x | ttl: 2d -->\n' "$(date +%Y-%m-%dT%H:%M)" > "$D/sub/snap.md"
printf '<!-- reviewed: 2026-13-45 -->\n' > "$D/daily/ignored.md"
printf 'no marker\n' > "$D/sub/plain.md"
expect_rc 0 "all fresh" sdw-docs-freshness --docs "$D" --brief
[ -z "$OUT" ] || fail "fresh brief is silent" "$OUT"
printf '<!-- fetched: %s | source: x -->\n' "$(date +%Y-%m-%d)" > "$D/sub/nottl.md"
expect_rc 1 "missing ttl is unknown" sdw-docs-freshness --docs "$D" --stale
printf '%s\n' "$OUT" | grep -q '^unknown .*sub/nottl.md' || fail "no ttl" "$OUT"
rm "$D/sub/nottl.md"
printf '<!-- reviewed: last week -->\n' > "$D/sub/bad.md"
expect_rc 1 "unparseable date is unknown" sdw-docs-freshness --docs "$D" --stale
printf '%s\n' "$OUT" | grep -q '^unknown .*sub/bad.md' || fail "bad date" "$OUT"
printf '%s\n' "$OUT" | grep -q 'ignored.md' && fail "daily skipped" "$OUT"
expect_rc 1 "brief names the problem" sdw-docs-freshness --docs "$D" --brief
[ "$(printf '%s\n' "$OUT" | grep -c .)" -le 2 ] && printf '%s' "$OUT" | grep -q '1 unknown' || fail "brief" "$OUT"
expect_rc 4 "docs dir missing" sdw-docs-freshness --docs "$tmp/none"

mkrepo "$tmp/plain"
expect_rc 0 "doctor not onboarded" sh -c "cd \"$tmp/plain\" && sdw-doctor"
[ "$(printf '%s\n' "$OUT" | grep -c '^PASS')" = 6 ] && printf '%s\n' "$OUT" | grep -qx 'PASS guard-read: .env blocked' || fail "doctor basic checks" "$OUT"
printf '%s\n' "$OUT" | grep -q '^PASS secrets: ' || fail "doctor secrets pass" "$OUT"

# Plaintext secrets in Claude config: names only, never the value.
S1='sk-Fixture9Value0Never1Shown' S2='Qz7pLm2Xv9Rt4Wn8Ks3J' S3='AbCdEf123456789xyz'
S4='Hd7Otel2Value9Hidden' S5='Ar9gValue8Hidden7Xy' S6='Fl4gEqValue3Hidden' S7='Qu3ryValue5Hidden' S8='Us3rPass9Hidden'
cat > "$HOME/.claude.json" <<EOF
{"mcpServers":{"logs":{"type":"http","url":"https://logs.invalid/mcp","headers":{"Authorization":"Bearer $S1"}},
 "ok":{"headers":{"Authorization":"Bearer \${LOGS_TOKEN}"},"env":{"DEBUG":"1","HOME_DIR":"/Users/someone/projects/x1"}}},
 "projects":{"/w/p":{"mcpServers":{"db":{"env":{"DB_PASSWORD":"$S2","TOKEN_URL":"https://auth.invalid/token"}}}}}}
EOF
mkdir -p "$HOME/.claude" "$tmp/plain/.claude"
printf '{"env":{"API_KEY":"%s","MODEL":"vendor-model-4-5-20250101","FLAG_TOKEN":"true","CLAUDE_CODE_MAX_OUTPUT_TOKENS":"128000","MAX_MCP_OUTPUT_TOKENS":"100000","CLAUDE_CODE_API_KEY_HELPER_TTL_MS":"3600000","OTEL_EXPORTER_OTLP_HEADERS":"Authorization=Bearer %s","NOTE":"renew the token every 300 s"}}\n' "$S1" "$S4" > "$HOME/.claude/settings.json"
cat > "$tmp/plain/.mcp.json" <<EOF
{"mcpServers":{"s":{"command":"x","env":{"X_OPT":"$S3","PORT":"8080"}},
 "a":{"command":"npx","args":["-y","pkg-server","--api-key","$S5","--token=$S6","--port","8080","--max-tokens","4096","--key","\${K}"]},
 "b":{"type":"sse","url":"https://mcp.invalid/sse?api_key=$S7"},"c":{"url":"https://u:$S8@mcp.invalid/x"},
 "d":{"url":"https://mcp.invalid/x?page=2&\${Q}"}}}
EOF
printf '{"env":{"SAFE":"${HOME}/x","EMPTY_SECRET":""}}\n' > "$tmp/plain/.claude/settings.local.json"
expect_rc 0 "doctor names plaintext secrets" sh -c "cd \"$tmp/plain\" && sdw-doctor"
W=$(printf '%s\n' "$OUT" | grep '^WARN secrets: ')
want="WARN secrets: ~/.claude.json: mcpServers.logs.headers.Authorization, projects[\"/w/p\"].mcpServers.db.env.DB_PASSWORD (use \${VAR} from Keychain, see docs/mcp.md; rotate the secret)
WARN secrets: ~/.claude/settings.json: env.API_KEY, env.OTEL_EXPORTER_OTLP_HEADERS (use \${VAR} from Keychain, see docs/mcp.md; rotate the secret)
WARN secrets: $tmp/plain/.mcp.json: mcpServers.s.env.X_OPT, mcpServers.a.args[3], mcpServers.a.args[4], mcpServers.b.url, mcpServers.c.url (use \${VAR} from Keychain, see docs/mcp.md; rotate the secret)"
[ "$W" = "$want" ] || fail "doctor secrets lines" "$W"
for v in "$S1" "$S2" "$S3" "$S4" "$S5" "$S6" "$S7" "$S8" Fixture9; do
  printf '%s' "$OUT" | grep -qF -- "$v" && fail "doctor secrets leak" "output contains $v"
done
ok "doctor secrets: names only"
printf '{"env":' > "$tmp/plain/.claude/settings.local.json"
expect_rc 0 "doctor bad settings JSON" sh -c "cd \"$tmp/plain\" && sdw-doctor"
printf '%s\n' "$OUT" | grep -qx "WARN secrets: $tmp/plain/.claude/settings.local.json: not valid JSON, not scanned" || fail "doctor bad JSON" "$OUT"
rm -rf "$HOME/.claude.json" "$HOME/.claude/settings.json" "$tmp/plain/.mcp.json" "$tmp/plain/.claude"
P="$tmp/proj"; mkdir -p "$P/.sdw"; mkrepo "$P/web"
printf 'web:. | fast: true\n' > "$P/.sdw/gates"
printf 'export PATH="$HOME/bin:$PATH"\n' > "$P/.sdw/env.sh"
(cd "$P" && sdw-exclude >/dev/null)
expect_rc 0 "doctor onboarded" sh -c "cd \"$P/web\" && sdw-doctor"
printf '%s\n' "$OUT" | grep -q '^WARN attribution: ' || fail "doctor attribution warns" "$OUT"
(cd "$P/web" && git commit -q --allow-empty -m x -m 'Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>')
expect_rc 0 "doctor in a repo with Claude trailers" sh -c "cd \"$P/web\" && sdw-doctor"
printf '%s\n' "$OUT" | grep -qx "PASS attribution: this repo's history carries Claude trailers" || fail "doctor attribution trailers" "$OUT"
printf 'broken line\n' > "$P/.sdw/gates"
expect_rc 1 "doctor fails on a broken gates file" sh -c "cd \"$P/web\" && sdw-doctor"
printf '%s\n' "$OUT" | grep -q '^FAIL gates:' || fail "doctor gates" "$OUT"
printf 'echo hi\n' > "$P/.sdw/env.sh"
expect_rc 1 "doctor fails on a noisy env.sh" sh -c "cd \"$P/web\" && sdw-doctor"
printf '%s\n' "$OUT" | grep -q '^FAIL env.sh' || fail "doctor env.sh" "$OUT"
rm "$P/.sdw/env.sh"; printf 'web:. | fast: true\n' > "$P/.sdw/gates"
python3 -c 'print("\n".join("- fact %d" % i for i in range(45)))' > "$P/.sdw/project.md"
expect_rc 0 "doctor warns on a long project.md" sh -c "cd \"$P/web\" && sdw-doctor"
printf '%s\n' "$OUT" | grep -q '^WARN project.md: 45 lines' || fail "doctor project.md" "$OUT"
rm "$P/.sdw/project.md"

# Keychain: doctor looks up exactly the items sdw-login reads (service per role, account per user).
printf 'PROJ_SLUG=shop\n' > "$P/.sdw/config.env"
printf '## login\n- kind: api\n## users\n- user: alice, bob\n' > "$P/.sdw/run.md"
mkdir -p "$tmp/kc"
cat > "$tmp/stub/security" <<'KC'
#!/bin/sh
s="" a=""
while [ $# -gt 0 ]; do case "$1" in -s) s=$2; shift 2 ;; -a) a=$2; shift 2 ;; *) shift ;; esac; done
[ -f "$KC_DIR/$s@@$a" ]
KC
chmod +x "$tmp/stub/security"
export KC_DIR="$tmp/kc"
: > "$tmp/kc/sdw:shop:user@@alice"; : > "$tmp/kc/sdw:shop:user-2@@bob"
expect_rc 0 "doctor keychain (wrong items)" sh -c "cd \"$P/web\" && sdw-doctor"
printf '%s\n' "$OUT" | grep -q '^WARN keychain: missing: sdw:shop:user (bob)' || fail "doctor keychain second user" "$OUT"
: > "$tmp/kc/sdw:shop:user@@bob"
expect_rc 0 "doctor keychain (as sdw-login reads)" sh -c "cd \"$P/web\" && sdw-doctor"
printf '%s\n' "$OUT" | grep -q '^PASS keychain' || fail "doctor keychain pass" "$OUT"
printf '## login\n- kind: header\n- header: x-user: {user}\n## users\n- user: carol, dan\n' > "$P/.sdw/run.md"
expect_rc 0 "doctor keychain (header recipe)" sh -c "cd \"$P/web\" && sdw-doctor"
printf '%s\n' "$OUT" | grep -q '^PASS keychain' || fail "doctor keychain header needs no secret" "$OUT"
printf '#!/bin/sh\nexit 0\n' > "$tmp/stub/security"
