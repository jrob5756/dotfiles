# Copilot CLI status line: receives the session status as JSON on stdin and
# prints "<session name> · #tag #tag · <session id>". Tags come from the
# terminal-tools plugin's session-tags database.
input="$(cat)"
name="$(jq -r '.session_name // ""' <<<"$input")"
id="$(jq -r '.session_id // ""' <<<"$input")"
tags=""
db="${SESSION_TAGS_DB:-${XDG_STATE_HOME:-$HOME/.local/state}/session-browser/tags.db}"
if [[ "$id" =~ ^[A-Za-z0-9-]+$ && -s "$db" ]]; then
  tags="$(sqlite3 -readonly "$db" "SELECT group_concat('#' || tag, ' ') FROM
    (SELECT tag FROM session_tags WHERE session_id = '$id' ORDER BY tag)" 2>/dev/null || true)"
fi
out=""
for part in "$name" "$tags" "$id"; do
  if [[ -n "$part" ]]; then out+="${out:+ · }$part"; fi
done
printf '%s\n' "$out"
