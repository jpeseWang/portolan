# The two blocks Portolan route adds to a Claude Code statusline script (here: ~/.claude/statusline.sh).
# Block 1 goes after the script has parsed H5/D7 (used percent) from the statusline JSON.
# Block 2 goes where segments are built; it needs NOW=$(date +%s), JQ, colours and add().

# ─── AI-TEAM QUOTA CACHE (read by ai-quota) ──────────────────────────────────
# AIM_HOME is exported by env.zsh; set it in your shell profile if the statusline runs without it.
AIM_STATE="${AIM_HOME:-$HOME/portolan/route}/state"
if [ -d "$AIM_STATE" ] && [ -z "${ANTHROPIC_BASE_URL:-}" ] \
   && [ "${H5:-}" -ge 0 ] 2>/dev/null && [ "${D7:-}" -ge 0 ] 2>/dev/null; then
  printf '{"h5":%s,"d7":%s,"acct":"%s","ts":%s}' "$H5" "$D7" \
    "$(basename "${CLAUDE_CONFIG_DIR:-claude}")" "$(date +%s)" > "$AIM_STATE/claude-rate.json.tmp" \
    && mv "$AIM_STATE/claude-rate.json.tmp" "$AIM_STATE/claude-rate.json"
fi

# DeepSeek balance from the route cache; refreshed in the background when older than 10 min
if [ "$SHOW_DS" = 1 ] && [ -f "$AIM_STATE/ds-balance.json" ]; then
  DS_BAL=$("$JQ" -r '.balance // empty' "$AIM_STATE/ds-balance.json" 2>/dev/null)
  DS_TS=$("$JQ" -r '.ts // 0' "$AIM_STATE/ds-balance.json" 2>/dev/null)
  if [ -n "$DS_BAL" ]; then
    DS_INT=${DS_BAL%.*}; DS_INT=${DS_INT:-0}
    if [ "$DS_INT" -ge 2 ]; then c="$GREEN"; elif [ "$DS_INT" -ge 1 ] || [ "${DS_BAL#0.[5-9]}" != "$DS_BAL" ]; then c="$WARN"; else c="$RED"; fi
    add "${c}ds:\$${DS_BAL}${R}"
  fi
  find "$AIM_STATE/.ds-refreshing" -mmin +5 -delete 2>/dev/null   # a killed refresh must not block the next one
  if [ $(( NOW - ${DS_TS:-0} )) -gt 600 ] && [ ! -e "$AIM_STATE/.ds-refreshing" ]; then
    ( touch "$AIM_STATE/.ds-refreshing"; python3 -I -B "$AIM_STATE/../ai-quota.py" --refresh-ds >/dev/null 2>&1; rm -f "$AIM_STATE/.ds-refreshing" ) >/dev/null 2>&1 &
  fi
fi
