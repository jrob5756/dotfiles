#!/usr/bin/env bash
# Browse Copilot CLI sessions with fzf, grouped by repository.
# Usage: session-browser [search term]
#   typing  search mode: re-runs the search over names, prompts and replies
#   ctrl-s  switch between search mode and fuzzy-filtering the loaded list
#   ctrl-t  toggle showing only open sessions
#   alt-a   toggle showing SDK sessions (e.g. conductor workflow agents; hidden by default)
#   ctrl-r  refresh sessions and open status
#   enter   resume the session in this pane
#   ctrl-o  open every visible session in tmux panes
#   tab     cycle the fields: session query, repo (repo names containing any of
#           its words) and tag (tags starting with any of its words; -tag
#           excludes, untagged matches sessions without tags)
#   alt-t   add or remove tags on the current or marked sessions
#   alt-g   group by tag instead of repo
#   ctrl-space  mark sessions; ctrl-x deletes the marked ones (or the current one)
#   ctrl-y  copy the session id; alt-y copies every visible session's id, one per line
#   ctrl-e  show the full history in the preview (default: the latest events)
#   ctrl-/  toggle preview layout
#   ?       show or hide this key list (on an empty query; otherwise types "?")
# Env: SESSION_BROWSER_RESUME_CMD (default "copilot --resume=")
#      SESSION_BROWSER_PANES_PER_WINDOW (default 6)
#      SESSION_BROWSER_COPILOT_CMD (default "copilot"; runs the hidden delete helper)
set -euo pipefail

COPILOT_DIR="${COPILOT_HOME:-$HOME/.copilot}"
DB="$COPILOT_DIR/session-store.db"
STATE="$COPILOT_DIR/session-state"
RESUME_CMD="${SESSION_BROWSER_RESUME_CMD:-copilot --resume=}"
PER_WINDOW="${SESSION_BROWSER_PANES_PER_WINDOW:-6}"
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
TAGS_CLI="$(command -v session-tags || true)"
TAGS_DB="${SESSION_TAGS_DB:-${XDG_STATE_HOME:-$HOME/.local/state}/session-browser/tags.db}"
TITLE_SUFFIX=" - GitHub Copilot"  # copilot titles its pane "<session name> - GitHub Copilot"

q() { sqlite3 -readonly -separator "${SEP:-$'\t'}" "$DB" "$1"; }
US=$'\x1f'  # unit separator: tabs are IFS whitespace, so empty fields would collapse
RS=$'\x1e'
esc() { printf '%s' "${1//\'/\'\'}"; }

# Temp paths removed on exit, including when fzf kills a stale preview or reload.
CLEANUP=()
trap 'rm -rf "${CLEANUP[@]}"' EXIT
trap 'exit 143' TERM HUP INT
scratch_dir() { mktemp -d "${TMPDIR:-/tmp}/session-browser.XXXXXX"; }

B=$'\033[1m'; D=$'\033[2m'; C=$'\033[36m'; Y=$'\033[33m'; G=$'\033[32m'; M=$'\033[35m'; R=$'\033[0m'

# --- session catalog --------------------------------------------------------
# Built from each session's workspace.yaml, the same source Copilot's Sessions
# tab uses; the session-store index is incomplete and only used for searching
# prompt text. Fields: id label cwd repo branch created updated sdk hasmsg.

read -r -d '' PARSE_WORKSPACE <<'AWK' || true
function unq(v,   c) {
  c = substr(v, 1, 1)
  if (c == "\"") {
    v = substr(v, 2, length(v) - 2)
    gsub(/\\n/, " ", v); gsub(/\\"/, "\"", v); gsub(/\\\\/, "\\", v)
  } else if (c == "\047") {
    v = substr(v, 2, length(v) - 2)
    gsub(/\047\047/, "\047", v)
  }
  return v
}
# sdk: created through the Copilot SDK (e.g. conductor workflow agents) and never
# resumed in the CLI, which would set last_client_name to github/cli.
function flush(   lab, sdk) {
  if (id == "") return
  lab = (name != "") ? name : summ
  gsub(/[\t\037\036]/, " ", lab)
  sdk = (client == "sdk" && (lastc == "" || lastc == "sdk")) ? 1 : 0
  printf "%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\036", id, substr(lab, 1, 100), cwd, repo, branch, created, updated, sdk, (lab != "") ? 1 : 0
}
FNR == 1 { flush(); id = name = summ = cwd = repo = branch = created = updated = client = lastc = block = "" }
block != "" && /^  / {
  if (block == "name" && name == "") { name = $0; sub(/^ +/, "", name) }
  if (block == "summary" && summ == "") { summ = $0; sub(/^ +/, "", summ) }
  next
}
{ block = "" }
/^id: /         { id = $2; next }
/^(name|summary): / {
  k = $1; sub(/:$/, "", k); v = $0; sub(/^[a-z]+: */, "", v)
  if (v ~ /^[|>]/) { block = k; next }
  if (k == "name") name = unq(v); else summ = unq(v)
  next
}
/^cwd: /        { cwd = unq(substr($0, 6)); next }
/^repository: / { repo = unq(substr($0, 13)); next }
/^branch: /     { branch = unq(substr($0, 9)); next }
/^created_at: / { created = $2; next }
/^updated_at: / { updated = $2; next }
/^client_name: /      { client = unq(substr($0, 14)); next }
/^last_client_name: / { lastc = unq(substr($0, 19)); next }
END { flush() }
AWK

# Writes the catalog (US/RS separated) to stdout. Unnamed sessions count only if
# they have a user message, matching Copilot's "unnamed sessions with no
# messages are not listed".
build_catalog() {
  local raw; raw="$(awk "$PARSE_WORKSPACE" "$STATE"/*/workspace.yaml)"
  local -a empties=()
  local rec
  while IFS= read -r -d "$RS" rec; do
    [[ "${rec##*"$US"}" == 0 ]] && empties+=("$STATE/${rec%%"$US"*}/events.jsonl")
  done <<<"$raw$RS"
  local withmsg=""
  if (( ${#empties[@]} )); then
    withmsg="$( { grep -l -m1 -F '"type":"user.message"' "${empties[@]}" 2>/dev/null || true; } | awk -F/ '{ print $(NF-1) }' | tr '\n' ' ')"
  fi
  printf '%s' "$raw" | awk -v RS="$RS" -v ORS="$RS" -F "$US" -v OFS="$US" -v withmsg=" $withmsg" '
    $9 == 0 && index(withmsg, " " $1 " ") { $9 = 1 } { print }'
}

catalog() {
  if [[ -n "${SESSION_BROWSER_CATALOG:-}" && -s "$SESSION_BROWSER_CATALOG" ]]; then
    cat "$SESSION_BROWSER_CATALOG"
  else
    build_catalog
  fi
}

# One session's fields from its workspace.yaml: label cwd repo branch created updated.
session_fields() {
  local f="$STATE/$1/workspace.yaml"
  [[ -f "$f" ]] || return 0
  awk "$PARSE_WORKSPACE" "$f" | awk -v RS="$RS" -F "$US" -v OFS="$US" 'NF { print $2, $3, $4, $5, $6, $7 }'
}
session_name() {
  local n; n="$(session_fields "$1" | cut -d "$US" -f1)"
  printf '%s' "${n:-${1:0:12}}"
}
session_cwd() {
  local dir; dir="$(session_fields "$1" | cut -d "$US" -f2)"
  [[ -n "$dir" && -d "$dir" ]] && printf '%s' "$dir" || printf '%s' "$HOME"
}

# --- open sessions ------------------------------------------------------------
# Prints "id<TAB>status<TAB>where" for sessions held by a live copilot process.
# An open session's process keeps $STATE/<id>/inuse.<pid>.hold open, so ask lsof
# which of those files copilot processes hold (stale lock files left by crashed
# processes don't count). A process can hold sessions it isn't showing
# (sidebar); a session is "open" in a pane only when that pane's title shows its
# name, otherwise it's "background".
inuse() {
  local pids
  pids="$(ps -axo pid=,comm= | awk '{ c = $2; sub(".*/", "", c) } c ~ /^copilot/ { print $1 }' | paste -sd, -)"
  [[ -n "$pids" ]] || return 0
  local held
  held="$(lsof -nP -a -p "$pids" -Fpn 2>/dev/null | awk -v state="$STATE/" '
    /^p/ { p = substr($0, 2); next }
    /^n/ && index($0, state) == 2 && $0 ~ /\/inuse\.[0-9]+\.hold$/ {
      n = substr($0, 2 + length(state)); split(n, a, "/"); print a[1] "\t" p }' | sort -u || true)"
  [[ -n "$held" ]] || return 0
  local -a files=()
  local id
  for id in $(cut -f1 <<<"$held" | sort -u); do
    [[ -f "$STATE/$id/workspace.yaml" ]] && files+=("$STATE/$id/workspace.yaml")
  done
  {
    ps -o pid=,tty=,comm= -p "$pids" 2>/dev/null | awk '{ c = $3; sub(".*/", "", c); print "P\t" $1 "\t" $2 "\t" c }' || true
    tmux list-panes -a -F $'T\t#{pane_tty}\t#{session_name}:#{window_index}.#{pane_index}\t#{pane_title}' 2>/dev/null || true
    awk '{ print "L\t" $0 }' <<<"$held"
    if (( ${#files[@]} )); then
      awk "$PARSE_WORKSPACE" "${files[@]}" | awk -v RS="$RS" -F "$US" 'NF { print "N\t" $1 "\t" $2 }'
    fi
  } | awk -F'\t' -v suffix="$TITLE_SUFFIX" '
    $1 == "P" { comm[$2] = $4; tty[$2] = $3; next }
    $1 == "T" { t = $2; sub("/dev/", "", t); loc[t] = $3; title[t] = $4; next }
    $1 == "N" { label[$2] = $3; next }
    $1 == "L" { lock[++n] = $2 "\t" $3; held[$3]++; next }
    END {
      for (i = 1; i <= n; i++) {
        split(lock[i], a, "\t"); id = a[1]; pid = a[2]
        if (!(pid in comm) || comm[pid] !~ /^copilot/) continue
        t = tty[pid]
        if (comm[pid] == "copilot-runtime") { add(id, "app", "Copilot app"); continue }
        if (!(t in loc)) { add(id, "open", "pid " pid); continue }
        shown = title[t]; sub(suffix "$", "", shown)
        # The title may carry the current activity too: "<name> - <intent>".
        if ((label[id] != "" && (shown == label[id] || index(shown, label[id] " - ") == 1)) ||
            (title[t] == "GitHub Copilot" && label[id] == "" && held[pid] == 1))
          add(id, "open", "tmux " loc[t])
        else
          add(id, "bg", "tmux " loc[t])
      }
      for (id in st) {
        w = (st[id] == "bg") ? "in the background of " bgw[id] : ow[id]
        printf "%s\t%s\t%s\n", id, st[id], w
      }
    }
    function add(id, s, w) {
      if (s == "bg") { bgw[id] = (id in bgw) ? bgw[id] ", " w : w; if (!(id in st)) st[id] = "bg"; return }
      ow[id] = (id in ow) ? ow[id] ", " w : w
      if (!(id in st) || st[id] == "bg" || s == "open") st[id] = s
    }'
}

# The preview runs on every cursor move, so it reuses recent inuse output (at
# most max_age seconds old). list passes 0 to refresh it.
inuse_cached() {
  local c="${SESSION_BROWSER_INUSE_CACHE:-}" max="${1:-5}" now="${EPOCHSECONDS:-$(date +%s)}" stamp=""
  [[ -n "$c" ]] || { inuse; return; }
  [[ -s "$c" ]] && read -r stamp < "$c"
  if [[ "$stamp" =~ ^[0-9]+$ ]] && (( now - stamp < max )); then tail -n +2 "$c"; return; fi
  local out; out="$(inuse)"
  { echo "$now"; if [[ -n "$out" ]]; then printf '%s\n' "$out"; fi; } > "$c.$$" && mv -f "$c.$$" "$c"
  [[ -z "$out" ]] || printf '%s\n' "$out"
}

# --- list ---------------------------------------------------------------------
OPEN_ONLY() { [[ -n "${SESSION_BROWSER_OPEN_ONLY_FILE:-}" && -s "$SESSION_BROWSER_OPEN_ONLY_FILE" ]]; }
SHOW_SDK() { [[ -n "${SESSION_BROWSER_SDK_FILE:-}" && -s "$SESSION_BROWSER_SDK_FILE" ]]; }
BY_TAG() { [[ -n "${SESSION_BROWSER_GROUP_FILE:-}" && -s "$SESSION_BROWSER_GROUP_FILE" ]]; }
REPO_SQL="coalesce(nullif(w.repo, ''), '(no repository)')"

# Repo field: sessions whose repo contains any of its space-separated words.
repo_cond() {
  [[ -s "${SESSION_BROWSER_REPO_FILE:-}" ]] || return 0
  local -a words; local cond="" word
  read -r -a words < <(tr '[:upper:]' '[:lower:]' < "$SESSION_BROWSER_REPO_FILE"; echo)
  for word in "${words[@]+"${words[@]}"}"; do cond+="${cond:+ OR }lower($REPO_SQL) LIKE '%$(esc "$word")%'"; done
  [[ -z "$cond" ]] || printf ' AND (%s)' "$cond"
}

# Tag field: sessions with a tag starting with any of its words; "-word"
# excludes, "untagged" matches sessions without tags.
tag_cond() {
  [[ -s "${SESSION_BROWSER_TAG_FILE:-}" ]] || return 0
  local -a words; local inc="" exc="" word neg c
  read -r -a words < <(tr '[:upper:]' '[:lower:]' < "$SESSION_BROWSER_TAG_FILE"; echo)
  for word in "${words[@]+"${words[@]}"}"; do
    neg=""; [[ "$word" == -* ]] && { neg=1; word="${word#-}"; }
    word="${word#\#}"
    [[ "$word" =~ ^[a-z0-9._/-]+$ ]] || continue
    if [[ "$word" == untagged ]]; then c="NOT EXISTS (SELECT 1 FROM st WHERE st.session_id = w.id)"
    else c="EXISTS (SELECT 1 FROM st WHERE st.session_id = w.id AND substr(st.tag, 1, ${#word}) = '$word')"; fi
    if [[ -n "$neg" ]]; then exc+=" AND NOT $c"; else inc+="${inc:+ OR }$c"; fi
  done
  [[ -z "$inc" ]] || printf ' AND (%s)' "$inc"
  printf '%s' "$exc"
}

# Session tags, copied into the in-memory db as st(session_id, tag).
TAGS_SQL_INIT="CREATE TABLE st(session_id TEXT, tag TEXT);"
tags_load_sql() {
  [[ -s "$TAGS_DB" ]] || return 0
  printf "ATTACH 'file:%s?mode=ro' AS tg; INSERT INTO st SELECT session_id, tag FROM tg.session_tags; DETACH tg;" "$TAGS_DB"
}

# awk: a stable color per tag, so "#proofs" looks the same everywhere.
read -r -d '' TAG_COLOR_AWK <<'AWK' || true
function tagcolor(t,   i, h) {
  h = 0
  for (i = 1; i <= length(t); i++) h = (h * 31 + index("abcdefghijklmnopqrstuvwxyz0123456789._/-", substr(t, i, 1))) % 9973
  return "\033[" substr("363233343531969293949591", (h % 12) * 2 + 1, 2) "m"
}
function tagline(s,   n, a, i, out) {
  n = split(s, a, " "); out = ""
  for (i = 1; i <= n; i++) out = out (i > 1 ? " " : "") tagcolor(a[i]) "#" a[i] "\033[0m"
  return out
}
AWK

list() {
  local term; term="$(esc "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')")"
  local tmp; tmp="$(scratch_dir)"; CLEANUP+=("$tmp")
  catalog > "$tmp/catalog"
  inuse_cached 0 | tr '\t' "$US" | awk -v RS='\n' -v ORS="$RS" '{ print }' > "$tmp/open"

  local where="1"
  if [[ -n "$term" ]]; then
    where="(lower(w.label) LIKE '%$term%' OR lower(w.repo) LIKE '%$term%' OR w.id IN (
              SELECT session_id FROM idx.turns
              WHERE lower(user_message) LIKE '%$term%' OR lower(assistant_response) LIKE '%$term%'))"
  fi
  local only=""; OPEN_ONLY && only="AND o.id IS NOT NULL"
  only+="$(repo_cond)$(tag_cond)"
  # SDK sessions (workflow agents) are hidden unless toggled on; count what's hidden.
  local sdk="" hidden="SELECT '#hidden', 0;"
  if ! SHOW_SDK; then
    sdk="AND w.sdk = 0"
    hidden="SELECT '#hidden', count(*) FROM ws w LEFT JOIN op o ON o.id = w.id
            WHERE w.sdk = 1 AND (w.hasmsg = 1 OR o.id IS NOT NULL) AND $where $only;"
  fi

  # Groups (repos, or tags with untagged last) ordered by their most recent
  # session, sessions newest first within each. By tag, a session appears under
  # each of its tags; the last column is its tags (by repo) or repo (by tag).
  local rows="SELECT h.*, h.repo AS grp, 0 AS untagged, h.tags AS extra FROM hits h"
  BY_TAG && rows="SELECT h.*, coalesce(s.tag, '(untagged)') AS grp, s.tag IS NULL AS untagged,
                    h.repo AS extra FROM hits h LEFT JOIN st s ON s.session_id = h.id"
  sqlite3 -separator $'\t' :memory: \
    "CREATE TABLE ws(id TEXT, label TEXT, cwd TEXT, repo TEXT, branch TEXT, created TEXT, updated TEXT, sdk INTEGER, hasmsg INTEGER);
     CREATE TABLE op(id, status, loc); $TAGS_SQL_INIT" \
    ".mode ascii" ".import '$tmp/catalog' ws" ".import '$tmp/open' op" ".mode list" ".separator \"\t\"" \
    "ATTACH 'file:$DB?mode=ro' AS idx; $(tags_load_sql)" \
    "$hidden" \
    "WITH hits AS (
       SELECT w.id, w.updated,
         $REPO_SQL AS repo,
         julianday('now') - julianday(w.updated) AS age,
         coalesce(nullif(w.label, ''), substr(w.id, 1, 12)) AS name,
         coalesce(o.status, '') AS status,
         coalesce((SELECT group_concat(tag, ' ') FROM (SELECT tag FROM st WHERE st.session_id = w.id ORDER BY tag)), '') AS tags
       FROM ws w LEFT JOIN op o ON o.id = w.id
       WHERE (w.hasmsg = 1 OR o.id IS NOT NULL)
         AND (o.id IS NOT NULL OR w.label NOT LIKE 'System:%')
         AND $where $only $sdk
       ORDER BY (o.id IS NOT NULL) DESC, w.updated DESC LIMIT 400),
     rows AS ($rows)
     SELECT id, grp, count(*) OVER (PARTITION BY grp),
       count(nullif(status, '')) OVER (PARTITION BY grp),
       CASE WHEN age < 1.0/24 THEN cast(age*1440 AS int) || 'm'
            WHEN age < 1      THEN cast(age*24 AS int) || 'h'
            WHEN age < 14     THEN cast(age AS int) || 'd'
            ELSE cast(age/7 AS int) || 'w' END,
       name, status, extra
     FROM rows
     ORDER BY untagged, max(updated) OVER (PARTITION BY grp) DESC, grp, updated DESC" |
  awk -F'\t' -v b="$B" -v y="$Y" -v d="$D" -v m="$M" -v r="$R" -v bytag="$(BY_TAG && echo 1)" "$TAG_COLOR_AWK"'
    $1 == "#hidden" { hidden = $2; next }
    $2 != prev {
      if (groups++) print "\t"
      extra = ($4 > 0) ? sprintf(", %s%d open%s%s", m, $4, r, d) : ""
      head = !bytag ? b y $2 r : ($2 == "(untagged)" ? b d $2 r : b tagcolor($2) "#" $2 r)
      printf "\t%s %s(%d%s)%s\n", head, d, $3, extra, r
      prev = $2
    }
    {
      mark = ($7 == "open" || $7 == "app") ? m "●" r : ($7 == "bg" ? d "◌" r : " ")
      if (bytag) { repo = $8; sub(".*/", "", repo); tail = "  " d repo r }
      else tail = ($8 != "") ? "  " tagline($8) : ""
      printf "%s\t %s %s%-4s%s  %s%s\n", $1, mark, d, $5, r, $6, tail
    }
    END {
      if (hidden > 0) {
        if (groups) print "\t"
        printf "\t%s%d SDK session%s hidden · alt-a to show%s\n", d, hidden, (hidden == 1 ? "" : "s"), r
      }
    }'
  rm -rf "$tmp"
}

# --- preview ------------------------------------------------------------------
# Renders the session's recent transcript roughly the way Copilot shows it on
# resume: shaded "❯" user blocks, "●" assistant messages with light markdown,
# and runs of commands/reads/searches/edits collapsed into one summary line.
# Read from the session's own events.jsonl (the session-store index lags and
# sometimes has no turns); subagent events carry a top-level agentId and are
# skipped. Records (US fields, RS terminated):
#   U <time> <text> | A - <text>
#   T <ok:true|false|running> <tool> <title> <detail> <mcp server> <result>

read -r -d '' EVENTS_TO_RECORDS <<'JQ' || true
def clean: tostring | gsub("[\u001e\u001f]"; " ");
def stamp: (try (sub("\\.[0-9]+Z$"; "Z") | fromdate) catch null) as $t
  | if $t == null then ""
    elif ($t | strflocaltime("%F")) == (now | strflocaltime("%F")) then $t | strflocaltime("%H:%M")
    else $t | strflocaltime("%b %e %H:%M") end;
def detail:
  if . == null then ""
  elif type != "object" then tostring
  else (.command // .path // .pattern // .description // .question // .message // .url // .query
        // .prompt // .summary // .fact // (to_entries | map("\(.key): \(.value | tostring)") | join(", "))) | tostring
  end | .[0:600] | gsub("\\s+"; " ") | ltrimstr(" ") | .[0:400];
(map(select(.type == "tool.execution_complete") | {key: .data.toolCallId, value: [(.data.success | tostring), (.data.result.content // "" | tostring | .[0:300] | gsub("\\s+"; " ") | ltrimstr(" ") | .[0:200])]})
  | from_entries) as $done
| .[]
| if .type == "user.message" then ["U", (.timestamp // "" | stamp), (.data.content // "")]
  elif .type == "assistant.message" then select((.data.content // "") != "") | ["A", "", .data.content]
  elif .type == "tool.execution_start" then .data as $d
    | ($done[$d.toolCallId] // ["running", ""]) as $r
    | ["T", $r[0], $d.toolName,
       ($d.mcpToolName // $d.toolTitle // ""), ($d.arguments | detail), ($d.mcpServerName // ""), $r[1]]
  else empty end
| map(clean) | join("\u001f") + "\u001e"
JQ

# Run with LC_ALL=C: widths count UTF-8 lead bytes, which BSD awk only matches
# byte-wise in the C locale.
read -r -d '' RENDER_TRANSCRIPT <<'AWK' || true
BEGIN {
  RS = "\036"; FS = "\037"; E = "\033["
  BLUE = E "38;2;68;147;248m"; TXT = E "38;2;183;191;220m"; GRAY = E "38;2;145;152;161m"
  GREEN = E "38;2;63;185;80m"; RED = E "38;2;248;81;73m"; YEL = E "38;2;249;226;175m"
  UBG = E "48;2;20;27;34m"; UFG = E "38;2;240;246;252m"; BOX = E "38;2;20;27;34m"
  CODE = E "38;2;255;255;255m" E "48;2;38;44;54m"; LINK = E "4m" E "38;2;148;226;213m"
  BOLD = E "1m"; RST = E "0m"; NB = "\302\240"
  if (W < 20) W = 20
}
function vlen(s) { gsub(/\033\[[0-9;]*m/, "", s); gsub(/[\200-\277]/, "", s); return length(s) }
function rep(c, n,   s) { s = ""; while (n-- > 0) s = s c; return s }
function trunc(s, n,   out, i, c, k) {
  if (vlen(s) <= n) return s
  out = ""; k = 0
  for (i = 1; i <= length(s); i++) {
    c = substr(s, i, 1)
    if (c !~ /[\200-\277]/ && ++k > n - 1) break
    out = out c
  }
  return out "…"
}
# Inline markdown: `code`, **bold**, [text](url).
function inline(s, base,   out, t) {
  out = ""
  while (match(s, /`[^`]+`|\*\*[^*]+\*\*|\[[^\]]+\]\([^)]+\)/)) {
    t = substr(s, RSTART, RLENGTH); out = out substr(s, 1, RSTART - 1)
    if (t ~ /^`/) { t = substr(t, 2, length(t) - 2); gsub(/ /, NB, t); out = out CODE NB t NB RST base }
    else if (t ~ /^\*\*/) out = out BOLD substr(t, 3, length(t) - 4) RST base
    else { sub(/\]\(.*/, "", t); out = out LINK substr(t, 2) RST base }
    s = substr(s, RSTART + RLENGTH)
  }
  return out s
}
# Word-wraps text into arr[1..k] lines of at most width columns.
function wrapto(text, width, arr,   n, w, i, k, line, ll, wl) {
  k = 0; line = ""; ll = 0; n = split(text, w, / +/)
  for (i = 1; i <= n; i++) {
    if (w[i] == "") continue
    wl = vlen(w[i])
    if (ll && ll + 1 + wl > width) { arr[++k] = line; line = ""; ll = 0 }
    line = ll ? line " " w[i] : w[i]; ll += (ll ? 1 : 0) + wl
  }
  if (ll || !k) arr[++k] = line
  return k
}
function emit(text, first, rest, width, base,   a, k, i) {
  k = wrapto(text, width, a)
  for (i = 1; i <= k; i++) print (i == 1 ? first : rest) base a[i] RST
}
function user(text, ts,   P, np, i, j, a, k, L, n, max, line, right) {
  gsub(/\t/, "    ", text); n = 0; max = 20
  np = split(text, P, "\n")
  for (i = 1; i <= np && n <= max; i++) {
    while (match(P[i], "[^ ]{" (W - 6) "}[^ ]")) P[i] = substr(P[i], 1, RSTART + W - 7) " " substr(P[i], RSTART + W - 6)
    k = wrapto(P[i], W - 6, a)
    for (j = 1; j <= k; j++) L[++n] = a[j]
  }
  if (n > max) { n = max; L[n] = "…" }
  print " " BOX rep("▄", W - 1) RST
  for (i = 1; i <= n; i++) {
    line = (i == 1 ? "❯ " : "  ") L[i]
    right = (i == 1 && ts != "" && vlen(line) + vlen(ts) + 4 <= W - 2) ? ts : ""
    print " " UBG " " UFG line rep(" ", W - 3 - vlen(line) - vlen(right)) GRAY right " " RST
  }
  print " " BOX rep("▀", W - 1) RST
}
function assistant(text,   L, n, i, l, pre, first, fence, blank, lead, mark, ind) {
  n = split(text, L, "\n"); first = 1; fence = 0; blank = 0
  for (i = 1; i <= n; i++) {
    l = L[i]; sub(/\r$/, "", l); gsub(/\t/, "    ", l)
    pre = first ? " " BLUE "●" RST " " : "   "
    if (l ~ /^ *```/) { fence = !fence; continue }
    if (!fence && l ~ /^ *$/) { blank = !first; continue }
    if (blank) { print ""; blank = 0 }
    if (fence || l ~ /^ *\|/) print pre GRAY trunc(l, W - 3) RST
    else if (l ~ /^#+ /) { sub(/^#+ +/, "", l); emit(inline(l, TXT BOLD), pre, "   ", W - 3, TXT BOLD) }
    else if (match(l, /^ *([-*+]|[0-9]+[.)]) +/)) {
      mark = substr(l, 1, RLENGTH); l = substr(l, RLENGTH + 1)
      lead = mark; sub(/[^ ].*/, "", lead); sub(/^ +/, "", mark); sub(/ +$/, "", mark)
      sub(/^[-*+]$/, "•", mark); ind = rep(" ", vlen(mark) + 1)
      emit(mark " " inline(l, TXT), pre lead, "   " lead ind, W - 3 - length(lead), TXT)
    }
    else emit(inline(l, TXT), pre, "   ", W - 3, TXT)
    first = 0
  }
  if (!first) print ""
}
function kind(t) {
  if (t ~ /^(bash|powershell|(read|write|stop|list)_(bash|powershell))$/) return "cmd"
  if (t == "view") return "read"
  if (t == "grep" || t == "glob") return "search"
  if (t == "edit" || t == "create" || t == "apply_patch") return "edit"
  return ""
}
function plural(n, one, many) { return n " " (n == 1 ? one : many) }
function flush(   s) {
  if (!gn) return
  s = ""
  if (gc["cmd"])    s = s ", " plural(gc["cmd"], "command", "commands")
  if (gc["read"])   s = s ", read " plural(gc["read"], "file", "files")
  if (gc["search"]) s = s ", " plural(gc["search"], "search", "searches")
  if (gc["edit"])   s = s ", edited " plural(gc["edit"], "file", "files")
  s = substr(s, 3); s = toupper(substr(s, 1, 1)) substr(s, 2)
  print "   " s
  if (gn == 1 && gk == "cmd") print "   " YEL "$ " GRAY trunc(gd, W - 5) RST
  else if (gn == 1 && gd != "") print "   " GRAY trunc(gd, W - 3) RST
  print ""
  gn = 0; delete gc
}
function tool(ok, name, title, det, server, res,   dot, head) {
  dot = (ok == "true") ? GREEN : (ok == "false") ? RED : GRAY
  if (title == "") title = name
  sub(/^Asking user$/, "Asked user", title)
  head = BOLD title RST " "
  if (server != "") det = "(MCP: " server ") · " det
  if (res != "") det = (det != "") ? det " " res : res
  print " " dot "●" RST " " head GRAY trunc(det, W - 4 - vlen(title)) RST
  print ""
}
$1 == "T" {
  if ($3 == "report_intent") next
  k = kind($3)
  if (k != "") { if (!gn) { gk = k; gd = $5 }; gn++; gc[k]++; next }
  flush(); tool($2, $3, $4, $5, $6, $7); next
}
$1 == "U" { flush(); user($3, $2); next }
$1 == "A" { flush(); assistant($3); next }
END { flush() }
AWK

# Default previews read only the end of the event log; "full" (ctrl-e) reads all of it.
PREVIEW_EVENTS=60
PREVIEW_BYTES=524288
FAST_GREP=grep; command -v rg >/dev/null 2>&1 && FAST_GREP=rg

preview() {
  [[ -z "${1:-}" ]] && exit 0
  local full=""; [[ "${2:-}" == full ]] && full=1
  local id; id="$(esc "$1")"
  local w="${FZF_PREVIEW_COLUMNS:-80}"
  local ev="$STATE/$1/events.jsonl"
  [[ -f "$ev" ]] || ev=""
  local tmp; tmp="$(scratch_dir)"; CLEANUP+=("$tmp")

  # inuse (lsof/ps) is the slowest step, so it runs alongside the transcript.
  inuse_cached > "$tmp/open" &
  local nprompts partial=""
  if [[ -n "$ev" ]]; then
    # The prompt count is the only full-file scan: run it alongside, with rg if present.
    { $FAST_GREP -F '"type":"user.message"' "$ev" | $FAST_GREP -vcF '},"agentId":"' || true; } > "$tmp/count" &
    if [[ -n "$full" ]]; then cat -- "$ev"; else tail -c "$PREVIEW_BYTES" "$ev" | tail -n +2; fi |
      grep -E '"type":"(user\.message|assistant\.message|tool\.execution_(start|complete))"' |
      grep -vF '},"agentId":"' > "$tmp/events" || true
    if [[ -z "$full" ]] && (( $(wc -l < "$tmp/events") > PREVIEW_EVENTS || $(wc -c < "$ev") > PREVIEW_BYTES )); then
      partial=1
      tail -n "$PREVIEW_EVENTS" "$tmp/events" > "$tmp/tail" && mv "$tmp/tail" "$tmp/events"
    fi
    jq -s -j "$EVENTS_TO_RECORDS" "$tmp/events" > "$tmp/records" || true
  else
    nprompts="$(q "SELECT count(*) FROM turns WHERE session_id = '$id'") turns"
    sqlite3 -readonly -ascii "$DB" \
      "SELECT kind, '', text FROM (
         SELECT turn_index, 0 AS o, 'U' AS kind, user_message AS text FROM turns
           WHERE session_id = '$id' AND coalesce(user_message, '') != ''
         UNION ALL
         SELECT turn_index, 1, 'A', assistant_response FROM turns
           WHERE session_id = '$id' AND coalesce(assistant_response, '') != '')
       ORDER BY turn_index DESC, o DESC LIMIT 60" |
      awk -v RS="$RS" -v ORS="$RS" '{ a[NR] = $0 } END { for (i = NR; i > 0; i--) if (a[i] != "") print a[i] }' \
      > "$tmp/records"
  fi
  wait
  if [[ -f "$tmp/count" ]]; then local n; n="$(tr -dc 0-9 < "$tmp/count")"; nprompts="${n:-0} prompts"; fi

  # Fixed 4-line header; the preview window pins it (~4) above the transcript.
  local label cwd repo branch created updated status loc c3 line3
  IFS="$US" read -r label cwd repo branch created updated < <(session_fields "$1"; echo) || true
  IFS=$'\t' read -r _ status loc < <(awk -F'\t' -v id="$1" '$1 == id' "$tmp/open"; echo) || true
  case "${status:-}" in
    open|app) c3="$B$M"; line3="● Open now: $loc" ;;
    bg)       c3="$D"; line3="◌ Loaded $loc" ;;
    *)        c3="$D"; line3="$cwd" ;;
  esac
  local line2="${repo:-—}${branch:+ ($branch)} · $nprompts · updated $(sed 's/T/ /' <<<"${updated:0:16}")"
  local name="${label:-${1:0:12}}" note="" rule tags=""
  [[ -s "$TAGS_DB" ]] && tags="$(sqlite3 -readonly "$TAGS_DB" \
    "SELECT group_concat(tag, ' ') FROM (SELECT tag FROM session_tags WHERE session_id = '$id' ORDER BY tag)" 2>/dev/null |
    awk "$TAG_COLOR_AWK"'NF { printf "  %s", tagline($0) }')"
  [[ -n "$partial" ]] && note=" last $PREVIEW_EVENTS events · ctrl-e full history "
  rule="──${note}$(printf '%*s' "$(( w - 2 - ${#note} ))" '' | sed 's/ /─/g')"
  printf '%s%s%s\n%s%s%s\n%s%s%s\n%s%s%s\n' \
    "$B$C" "${name:0:$w}" "$R$tags" "$Y" "${line2:0:$w}" "$R" "$c3" "${line3:0:$w}" "$R" \
    "$D" "${rule:0:$w}" "$R"
  LC_ALL=C awk -v W="$w" "$RENDER_TRANSCRIPT" "$tmp/records"
  rm -rf "$tmp"
}

# --- resume -------------------------------------------------------------------
# Resume one session in the current pane, warning if it is already open.
open_here() {
  local id="$1" where
  where="$(inuse | awk -F'\t' -v id="$id" '$1 == id { print $3 }')"
  if [[ -n "$where" ]]; then
    printf '%s⚠ "%s" is already open (%s).%s\n' "$B$Y" "$(session_name "$id")" "$where" "$R"
    read -r -p "Resume it here anyway? [y/N] " ans
    [[ "$ans" =~ ^[Yy] ]] || exit 0
  fi
  cd "$(session_cwd "$id")"
  exec $RESUME_CMD"$id"
}

# Print the ids in file $1 (fzf {*f}) once each, in list order; group header
# lines have no id, and grouped by tag a session can be listed more than once.
list_ids() { awk -F'\t' '$1 != "" && !seen[$1]++ { print $1 }' "$1"; }

# Open every session listed in file $1 (fzf {*f}) in tmux panes,
# PER_WINDOW panes per new window.
open_all() {
  if [[ -z "${TMUX:-}" ]]; then
    echo "Resume-all needs to run inside tmux."; read -r -p "Press enter to go back. " _; return
  fi

  local -a ids=() free=() busy=() chosen=()
  local id line
  # Grouped by tag, a session can be listed (and marked) more than once.
  while IFS= read -r line; do id="${line%%$'\t'*}"; [[ -n "$id" && " ${ids[*]-} " != *" $id "* ]] && ids+=("$id"); done < "$1"
  (( ${#ids[@]} )) || return

  local open_map; open_map="$(inuse)"
  for id in "${ids[@]}"; do
    if grep -q "^$id"$'\t' <<<"$open_map"; then busy+=("$id"); else free+=("$id"); fi
  done

  clear
  printf '%sResume %d visible session(s)%s\n\n' "$B" "${#ids[@]}" "$R"
  if (( ${#busy[@]} )); then
    printf '%s⚠ %d of them are already open:%s\n' "$B$Y" "${#busy[@]}" "$R"
    for id in "${busy[@]}"; do
      printf '  %s●%s %s %s(%s)%s\n' "$M" "$R" "$(session_name "$id")" "$D" \
        "$(awk -F'\t' -v id="$id" '$1 == id { print $3 }' <<<"$open_map")" "$R"
    done
    printf '\nResume those anyway?  %s[a]%s all   %s[n]%s none   %s[s]%s select   %s[c]%s cancel\n' \
      "$B" "$R" "$B" "$R" "$B" "$R" "$B" "$R"
    local ans; read -r -n1 -p "> " ans; echo
    case "$ans" in
      a|A) chosen=("${busy[@]}") ;;
      s|S)
        local picked
        picked="$(for id in "${busy[@]}"; do printf '%s\t%s\n' "$id" "$(session_name "$id")"; done |
          fzf --multi --height=100% --delimiter=$'\t' --with-nth=2 \
              --header='tab toggle · ctrl-a all · enter confirm · esc none' \
              --bind='ctrl-a:select-all' --prompt='resume anyway › ' || true)"
        while IFS= read -r line; do id="${line%%$'\t'*}"; [[ -n "$id" ]] && chosen+=("$id"); done <<<"$picked"
        ;;
      c|C) return ;;
      *) ;;
    esac
  fi

  local -a todo=("${free[@]+"${free[@]}"}" "${chosen[@]+"${chosen[@]}"}")
  if (( ${#todo[@]} == 0 )); then
    read -r -p "Nothing to open. Press enter to go back. " _; return
  fi
  local windows=$(( (${#todo[@]} + PER_WINDOW - 1) / PER_WINDOW ))
  if (( ${#todo[@]} > PER_WINDOW )); then
    read -r -p "Open ${#todo[@]} sessions across $windows tmux windows? [Y/n] " ans
    [[ "$ans" =~ ^[Nn] ]] && return
  fi

  local i win="" first="" cmd name dir pane
  for i in "${!todo[@]}"; do
    id="${todo[$i]}"; name="$(session_name "$id")"; dir="$(session_cwd "$id")"
    cmd="$RESUME_CMD$id || { echo 'copilot exited with an error; press enter to close'; read _; }"
    if (( i % PER_WINDOW == 0 )); then
      pane="$(tmux new-window -d -P -F '#{pane_id}' -n "sessions-$(( i / PER_WINDOW + 1 ))" -c "$dir" "$cmd")"
      win="$(tmux display-message -p -t "$pane" '#{window_id}')"
      [[ -z "$first" ]] && first="$win"
      tmux set-option -w -t "$win" pane-border-status top
      tmux set-option -w -t "$win" pane-border-format ' #{@session_browser_name} '
    else
      pane="$(tmux split-window -d -P -F '#{pane_id}' -t "$win" -c "$dir" "$cmd")"
      tmux select-layout -t "$win" tiled >/dev/null
    fi
    tmux set-option -p -t "$pane" @session_browser_name "$name"
  done
  tmux select-window -t "$first"
}

# --- delete -------------------------------------------------------------------
# Copilot has no non-interactive delete (`copilot -p` sends slash commands to
# the model), so drive a hidden interactive CLI on a private tmux server and
# type "/session delete <id> --yes" for each session. The helper always uses
# one fixed session id so it never leaves new empty sessions behind.
COPILOT_CMD="${SESSION_BROWSER_COPILOT_CMD:-copilot}"

helper_id() {
  local f="${XDG_STATE_HOME:-$HOME/.local/state}/session-browser/helper-session-id"
  if [[ ! -s "$f" ]]; then
    mkdir -p "$(dirname "$f")"
    uuidgen | tr '[:upper:]' '[:lower:]' > "$f"
  fi
  cat "$f"
}

# Delete the sessions listed in file $1 (fzf {+f}); open sessions are skipped.
delete_sessions() {
  local -a ids=() targets=() skipped=() deleted=()
  local id line ans
  # Grouped by tag, a session can be listed (and marked) more than once.
  while IFS= read -r line; do id="${line%%$'\t'*}"; [[ -n "$id" && " ${ids[*]-} " != *" $id "* ]] && ids+=("$id"); done < "$1"
  (( ${#ids[@]} )) || return 0

  local open_map; open_map="$(inuse)"
  for id in "${ids[@]}"; do
    if grep -q "^$id"$'\t' <<<"$open_map"; then skipped+=("$id"); else targets+=("$id"); fi
  done

  clear
  if (( ${#skipped[@]} )); then
    printf '%sSkipping %d open session(s); close them first:%s\n' "$B$Y" "${#skipped[@]}" "$R"
    for id in "${skipped[@]}"; do printf '  %s●%s %s\n' "$M" "$R" "$(session_name "$id")"; done
    echo
  fi
  if (( ${#targets[@]} == 0 )); then
    read -r -p "Nothing to delete. Press enter to go back. " _; return 0
  fi

  local synced=0
  local -A names=()
  printf '%sDelete %d session(s)?%s Their local history is removed for good.\n' "$B" "${#targets[@]}" "$R"
  for id in "${targets[@]}"; do
    names[$id]="$(session_name "$id")"
    printf '  %s\n' "${names[$id]}"
    grep -q '^mc_task_id:' "$STATE/$id/workspace.yaml" 2>/dev/null && synced=$((synced + 1))
  done
  read -r -p "Delete? [y/N] " ans
  [[ "$ans" =~ ^[Yy] ]] || return 0
  local remote=0
  if (( synced )); then
    read -r -p "$synced of them are synced to your GitHub account. Delete the synced copies too? [y/N] " ans
    [[ "$ans" =~ ^[Yy] ]] && remote=1
  fi

  printf '\nStarting a hidden Copilot CLI to run /session delete...\n'
  local sock="session-browser-delete-$$" hid screen i
  hid="$(helper_id)"
  tmux -L "$sock" -f /dev/null new-session -d -s h -x 200 -y 50 -c "$HOME" \
    "env -u TMUX $COPILOT_CMD --session-id $hid"
  local sockpath; sockpath="$(tmux -L "$sock" display-message -p '#{socket_path}')"
  trap "tmux -L '$sock' kill-server 2>/dev/null || true; rm -f '$sockpath'" EXIT

  # Wait for the input prompt, answering the folder-trust question if asked.
  local ready=0
  for i in $(seq 1 120); do
    screen="$(tmux -L "$sock" capture-pane -p -t h 2>/dev/null)" || break
    if grep -q 'remember this folder' <<<"$screen"; then
      tmux -L "$sock" send-keys -t h Enter; sleep 1; continue   # option 1: trust for this session only
    fi
    if grep -q 'open sidebar' <<<"$screen"; then ready=1; break; fi
    sleep 0.5
  done
  if (( ! ready )); then
    printf '%sThe helper Copilot CLI did not start.%s\n' "$B$Y" "$R"
    read -r -p "Press enter to go back. " _; return 0
  fi
  sleep 1

  local result last answered
  for id in "${targets[@]}"; do
    tmux -L "$sock" send-keys -t h -l "/session delete $id --yes"
    sleep 0.3
    tmux -L "$sock" send-keys -t h Enter
    result="timed out"; answered=0
    for i in $(seq 1 60); do
      sleep 0.5
      screen="$(tmux -L "$sock" capture-pane -p -t h -S -400)"
      last="$(grep -F "$id" <<<"$screen" | tail -1 || true)"
      if [[ "$last" == *"Deleted session"* ]]; then result="deleted"; break; fi
      if [[ "$last" == *"✗"* ]]; then result="${last#*✗ }"; break; fi
      if (( ! answered )) && [[ "$last" == *"has been synced to your account"* ]]; then
        (( remote )) && tmux -L "$sock" send-keys -t h Down && sleep 0.2
        tmux -L "$sock" send-keys -t h Enter
        answered=1
      fi
    done
    if [[ "$result" == deleted ]]; then
      deleted+=("$id")
      printf '  %s✓%s %s\n' "$G" "$R" "${names[$id]}"
    else
      printf '  %s✗%s %s %s(%s)%s\n' "$Y" "$R" "${names[$id]}" "$D" "$result" "$R"
    fi
  done

  if (( ${#deleted[@]} )) && [[ -x "$TAGS_CLI" ]]; then "$TAGS_CLI" forget "${deleted[@]}" || true; fi

  tmux -L "$sock" send-keys -t h -l "/exit"
  tmux -L "$sock" send-keys -t h Enter
  sleep 1
  echo
  read -r -p "Press enter to go back. " _
}

# --- tag picker ---------------------------------------------------------------
# alt-t: toggle tags on the current or marked sessions ($1 = fzf {+f} file).
tag_picker() {
  local -a ids=(); local id line
  while IFS= read -r line; do id="${line%%$'\t'*}"; [[ -n "$id" ]] && ids+=("$id"); done < "$1"
  (( ${#ids[@]} )) || return 0
  if [[ ! -x "$TAGS_CLI" ]]; then
    echo "session-tags not found on PATH"; read -r -p "Press enter to go back. " _; return 0
  fi
  SESSION_BROWSER_PICK_FILE="$(mktemp "${TMPDIR:-/tmp}/session-browser-pick.XXXXXX")"
  export SESSION_BROWSER_PICK_FILE; CLEANUP+=("$SESSION_BROWSER_PICK_FILE")
  printf '%s\n' "${ids[@]}" | sort -u > "$SESSION_BROWSER_PICK_FILE"
  local n what; n="$(wc -l < "$SESSION_BROWSER_PICK_FILE" | tr -d ' ')"
  if (( n == 1 )); then what="$(session_name "${ids[0]}")"; else what="$n sessions"; fi
  tag_list "" | fzf --ansi --no-sort --height=100% --layout=reverse --border=rounded \
    --border-label=" tags · $what " --border-label-pos=3 \
    --delimiter=$'\t' --with-nth=2.. --prompt='tag › ' --ghost='filter tags, or type a new one' \
    --header='enter toggle · type a new tag + enter to add it · esc done' \
    --bind="change:reload($SELF --tag-list {q})" \
    --bind="enter:transform($SELF --tag-toggle {1})" >/dev/null || true
}

# Picker lines "tag<TAB>display": ✓ on every target session, ◐ on some; a
# "+ add" line first when the query is a new valid tag, so enter adds what was
# typed rather than toggling an existing tag it happens to fuzzy-match.
tag_list() {
  local q n ids rows=""
  q="$(printf '%s' "${1:-}" | sed 's/^#//' | tr '[:upper:]' '[:lower:]')"
  n="$(wc -l < "$SESSION_BROWSER_PICK_FILE" | tr -d ' ')"
  ids="$(sed "s/.*/'&'/" "$SESSION_BROWSER_PICK_FILE" | paste -sd, -)"
  [[ -s "$TAGS_DB" ]] && rows="$(sqlite3 -readonly -separator $'\t' "$TAGS_DB" \
    "SELECT tag, count(*), sum(session_id IN ($ids)) FROM session_tags GROUP BY tag
     ORDER BY sum(session_id IN ($ids)) > 0 DESC, count(*) DESC, tag")"
  if [[ "$q" =~ ^[a-z0-9][a-z0-9._/-]{0,39}$ ]] && ! grep -q "^$q"$'\t' <<<"$rows"; then
    printf '%s\t%s+ add%s #%s\n' "$q" "$G" "$R" "$q"
  fi
  [[ -z "$rows" ]] || awk -F'\t' -v n="$n" -v d="$D" -v g="$G" -v r="$R" "$TAG_COLOR_AWK"'
    { mark = ($3 == n) ? g "✓" r : ($3 > 0 ? d "◐" r : " ")
      printf "%s\t%s %s#%s%s  %s(%d)%s\n", $1, mark, tagcolor($1), $1, r, d, $2, r }' <<<"$rows"
  return 0
}

# fzf transform: add the tag to every target session, or remove it if all have it.
tag_toggle() {
  local tag="${1:-}" n k
  [[ -n "$tag" ]] || exit 0
  local -a args=(); local id
  while IFS= read -r id; do args+=(-s "$id"); done < "$SESSION_BROWSER_PICK_FILE"
  n="$(wc -l < "$SESSION_BROWSER_PICK_FILE" | tr -d ' ')"
  k=0
  [[ -s "$TAGS_DB" ]] && k="$(sqlite3 -readonly "$TAGS_DB" "SELECT count(*) FROM session_tags
    WHERE tag = '$(esc "$tag")' AND session_id IN ($(sed "s/.*/'&'/" "$SESSION_BROWSER_PICK_FILE" | paste -sd, -))")"
  if (( k == n )); then "$TAGS_CLI" rm "${args[@]}" "$tag" >&2; else "$TAGS_CLI" add "${args[@]}" "$tag" >&2; fi
  echo "clear-query+reload($SELF --tag-list)"
}

# --- fzf actions --------------------------------------------------------------
# The input box holds three fields and tab cycles them: the session query
# (server-side "search" or local fuzzy "filter", see ctrl-s), the repo filter
# and the tag filter. The border label shows the fields not being edited.
# State files: MODE (search|filter), FIELD (empty, repo or tag), QUERY (search
# text), FUZZY (filter text, saved while editing another field), REPO, TAG.
mode() { local m; m="$(cat "${SESSION_BROWSER_MODE_FILE:-/dev/null}" 2>/dev/null)"; printf '%s' "${m:-search}"; }
field() { local f; f="$(cat "${SESSION_BROWSER_FIELD_FILE:-/dev/null}" 2>/dev/null)"; printf '%s' "${f:-query}"; }
field_file() {  # the state file holding field $1's text
  case "$1" in
    repo) printf '%s' "$SESSION_BROWSER_REPO_FILE" ;;
    tag)  printf '%s' "$SESSION_BROWSER_TAG_FILE" ;;
    *)    if [[ "$(mode)" == filter ]]; then printf '%s' "$SESSION_BROWSER_FUZZY_FILE"; else printf '%s' "$SESSION_BROWSER_QUERY_FILE"; fi ;;
  esac
}

prompt_for() {
  local name tags=""
  name="$(field)"; [[ "$name" == query ]] && name="$(mode)"
  BY_TAG && tags="by tag"
  OPEN_ONLY && tags="${tags:+$tags, }open"
  SHOW_SDK && tags="${tags:+$tags, }+sdk"
  if [[ -n "$tags" ]]; then printf '%s (%s) › ' "$name" "$tags"; else printf '%s › ' "$name"; fi
}

ghost_for() {
  case "$(field)" in
    repo) printf 'part of a repo name; spaces separate alternatives' ;;
    tag)  printf 'tags or their start; -tag excludes; untagged' ;;
    *)    if [[ "$(mode)" == filter ]]; then printf 'fuzzy-filter the loaded list'; else printf 'session names, prompts and replies'; fi ;;
  esac
}

label_text() {
  local d=$'\033[2m' r=$'\033[0m' cur f name value out=""
  cur="$(field)"
  for f in query repo tag; do
    [[ "$f" == "$cur" ]] && continue
    name="$f"; [[ "$f" == query ]] && name="$(mode)"
    value="$(cat "$(field_file "$f")" 2>/dev/null)"
    if [[ -z "${value//[[:space:]]/}" ]]; then
      case "$f" in repo|tag) value="${d}all${r}" ;; *) value="${d}—${r}" ;; esac
    fi
    out+="${out:+  ${d}·${r}  }$name: $value"
  done
  printf ' %s  %s· tab%s ' "$out" "$d" "$r"
}

# fzf transform: tab ($1 = 1) or shift-tab ($1 = -1) moves to the next field.
switch_field() {
  local cur next i
  local -a order=(query repo tag)
  cur="$(field)"
  for i in 0 1 2; do [[ "${order[$i]}" == "$cur" ]] && break; done
  next="${order[$(( (i + ${1:-1} + 3) % 3 ))]}"
  printf '%s' "${FZF_QUERY:-}" > "$(field_file "$cur")"
  if [[ "$next" == query ]]; then
    : > "$SESSION_BROWSER_FIELD_FILE"
    [[ "$(mode)" == filter ]] && printf 'unbind(change)+enable-search+'
  else
    printf '%s' "$next" > "$SESSION_BROWSER_FIELD_FILE"
    printf 'rebind(change)+disable-search+'
  fi
  printf "transform-query(cat '%s')+" "$(field_file "$next")"
  echo "change-prompt($(prompt_for))+change-ghost($(ghost_for))+transform-border-label($SELF --label)+reload($SELF --list-saved)"
}

# fzf action: refresh the prompt tags and reload.
reprompt_reload() {
  echo "change-prompt($(prompt_for))+reload($SELF --list-saved)"
}

# Compact header by default; "?" expands it to the full key list.
header_text() {
  local k=$'\033[36m' d=$'\033[2m' r=$'\033[0m'
  if [[ -s "${SESSION_BROWSER_KEYS_FILE:-}" ]]; then
    printf '%s\n' \
      "● open  ◌ background  ${d}·${r}  ${k}?${r} hide keys" \
      "${k}enter ${r} resume        ${k}ctrl-o${r} resume all    ${k}ctrl-x${r} delete        ${k}ctrl-space${r} mark" \
      "${k}tab   ${r} next field    ${k}ctrl-s${r} search↔filter ${k}ctrl-t${r} open only     ${k}alt-a${r} SDK sessions" \
      "${k}alt-t ${r} tag           ${k}alt-g ${r} group by tag  ${k}ctrl-r${r} refresh       ${k}ctrl-e${r} full history" \
      "${k}ctrl-/${r} layout        ${k}ctrl-y${r} copy id       ${k}alt-y ${r} copy all ids"
  else
    printf '%s\n' "● open  ◌ background  ${d}·${r}  ${k}enter${r} resume  ${d}·${r}  ${k}tab${r} repo/tag  ${d}·${r}  ${k}alt-t${r} tag  ${d}·${r}  ${k}?${r} keys"
  fi
}

case "${1:-}" in
  --preview)   preview "${2:-}" "${3:-}"; exit ;;
  # fzf transform on typing: the reload names the field being edited now, so a
  # tab pressed during its debounce can't send this text to the next field.
  --on-change) echo "reload(sleep 0.2; $SELF --list $(field) {q})"; exit ;;
  --list)  # $2 = field, $3 = its text
    if [[ "${2:-}" != query ]]; then
      printf '%s' "${3:-}" > "$(field_file "$2")"
      list "$(cat "$SESSION_BROWSER_QUERY_FILE" 2>/dev/null)"
    else
      [[ -n "${SESSION_BROWSER_QUERY_FILE:-}" ]] && printf '%s' "${3:-}" > "$SESSION_BROWSER_QUERY_FILE"
      list "${3:-}"
    fi
    exit ;;
  --list-saved) list "$(cat "$SESSION_BROWSER_QUERY_FILE" 2>/dev/null)"; exit ;;
  --refresh)
    build_catalog > "$SESSION_BROWSER_CATALOG"
    list "$(cat "$SESSION_BROWSER_QUERY_FILE" 2>/dev/null)"; exit ;;
  # fzf transform: flip between server-side search and local fuzzy filter.
  # From the repo or tag field it only flips the mode shown in the label.
  --toggle-mode)
    if [[ "$(mode)" == search ]]; then
      echo filter > "$SESSION_BROWSER_MODE_FILE"; : > "$SESSION_BROWSER_FUZZY_FILE"
      if [[ "$(field)" != query ]]; then echo "transform-border-label($SELF --label)"; exit; fi
      echo "unbind(change)+change-prompt($(prompt_for))+change-ghost($(ghost_for))+enable-search+clear-query"
    else
      echo search > "$SESSION_BROWSER_MODE_FILE"
      if [[ "$(field)" != query ]]; then echo "transform-border-label($SELF --label)"; exit; fi
      echo "rebind(change)+change-prompt($(prompt_for))+change-ghost($(ghost_for))+disable-search+reload($SELF --list-saved)+transform-query(cat \"\$SESSION_BROWSER_QUERY_FILE\")"
    fi
    exit ;;
  --switch-field) switch_field "${2:-1}"; exit ;;
  --label)        label_text; exit ;;
  # fzf transforms: toggle showing only open sessions, SDK sessions too, or
  # grouping by tag instead of repo.
  --toggle-open|--toggle-sdk|--toggle-group)
    case "$1" in
      --toggle-open) f="$SESSION_BROWSER_OPEN_ONLY_FILE" ;;
      --toggle-sdk)  f="$SESSION_BROWSER_SDK_FILE" ;;
      *)             f="$SESSION_BROWSER_GROUP_FILE" ;;
    esac
    if [[ -s "$f" ]]; then : > "$f"; else echo 1 > "$f"; fi
    reprompt_reload
    exit ;;
  # fzf transform: "?" on an empty query toggles the key list; otherwise it's typed.
  --toggle-keys)
    if [[ -n "${FZF_QUERY:-}" ]]; then echo put; exit; fi
    if [[ -s "$SESSION_BROWSER_KEYS_FILE" ]]; then : > "$SESSION_BROWSER_KEYS_FILE"; else echo 1 > "$SESSION_BROWSER_KEYS_FILE"; fi
    echo "transform-header($SELF --header)"
    exit ;;
  --header)    header_text; exit ;;
  --inuse)     inuse; exit ;;
  --open-here) open_here "$2"; exit ;;
  --open-all)  open_all "$2"; exit ;;
  --ids)       list_ids "$2"; exit ;;
  --delete)    delete_sessions "$2"; exit ;;
  --tag-picker) tag_picker "$2"; exit ;;
  --tag-list)   tag_list "${2:-}"; exit ;;
  --tag-toggle) tag_toggle "${2:-}"; exit ;;
esac

TERM_ARG="${*:-}"
SESSION_BROWSER_CATALOG="$(mktemp "${TMPDIR:-/tmp}/session-browser-catalog.XXXXXX")"
SESSION_BROWSER_QUERY_FILE="$(mktemp "${TMPDIR:-/tmp}/session-browser-query.XXXXXX")"
SESSION_BROWSER_OPEN_ONLY_FILE="$(mktemp "${TMPDIR:-/tmp}/session-browser-open.XXXXXX")"
SESSION_BROWSER_SDK_FILE="$(mktemp "${TMPDIR:-/tmp}/session-browser-sdk.XXXXXX")"
SESSION_BROWSER_INUSE_CACHE="$(mktemp "${TMPDIR:-/tmp}/session-browser-inuse.XXXXXX")"
SESSION_BROWSER_KEYS_FILE="$(mktemp "${TMPDIR:-/tmp}/session-browser-keys.XXXXXX")"
SESSION_BROWSER_REPO_FILE="$(mktemp "${TMPDIR:-/tmp}/session-browser-repo.XXXXXX")"
SESSION_BROWSER_FIELD_FILE="$(mktemp "${TMPDIR:-/tmp}/session-browser-field.XXXXXX")"
SESSION_BROWSER_MODE_FILE="$(mktemp "${TMPDIR:-/tmp}/session-browser-mode.XXXXXX")"
SESSION_BROWSER_FUZZY_FILE="$(mktemp "${TMPDIR:-/tmp}/session-browser-fuzzy.XXXXXX")"
SESSION_BROWSER_TAG_FILE="$(mktemp "${TMPDIR:-/tmp}/session-browser-tag.XXXXXX")"
SESSION_BROWSER_GROUP_FILE="$(mktemp "${TMPDIR:-/tmp}/session-browser-group.XXXXXX")"
export SESSION_BROWSER_CATALOG SESSION_BROWSER_QUERY_FILE SESSION_BROWSER_OPEN_ONLY_FILE SESSION_BROWSER_SDK_FILE SESSION_BROWSER_INUSE_CACHE SESSION_BROWSER_KEYS_FILE \
  SESSION_BROWSER_REPO_FILE SESSION_BROWSER_FIELD_FILE SESSION_BROWSER_MODE_FILE SESSION_BROWSER_FUZZY_FILE \
  SESSION_BROWSER_TAG_FILE SESSION_BROWSER_GROUP_FILE
CLEANUP+=("$SESSION_BROWSER_CATALOG" "$SESSION_BROWSER_QUERY_FILE" "$SESSION_BROWSER_OPEN_ONLY_FILE" "$SESSION_BROWSER_SDK_FILE" "$SESSION_BROWSER_INUSE_CACHE" "$SESSION_BROWSER_KEYS_FILE" \
  "$SESSION_BROWSER_REPO_FILE" "$SESSION_BROWSER_FIELD_FILE" "$SESSION_BROWSER_MODE_FILE" "$SESSION_BROWSER_FUZZY_FILE" \
  "$SESSION_BROWSER_TAG_FILE" "$SESSION_BROWSER_GROUP_FILE")
[[ -x "$TAGS_CLI" ]] && { "$TAGS_CLI" gc >/dev/null 2>&1 || true; }  # drop tags of deleted sessions
build_catalog > "$SESSION_BROWSER_CATALOG"
printf '%s' "$TERM_ARG" > "$SESSION_BROWSER_QUERY_FILE"
list "$TERM_ARG" | fzf --ansi --no-sort --multi --height=100% --delimiter=$'\t' --with-nth=2.. \
  --disabled --query="$TERM_ARG" --prompt="$(prompt_for)" --ghost="$(ghost_for)" \
  --header="$(header_text)" \
  --layout=reverse --border=rounded --border-label="$(label_text)" --border-label-pos=3 \
  --bind="tab:transform($SELF --switch-field 1)" \
  --bind="btab:transform($SELF --switch-field -1)" \
  --bind="ctrl-space:toggle+down" \
  --bind="?:transform($SELF --toggle-keys)" \
  --bind="change:transform($SELF --on-change)" \
  --bind="ctrl-s:transform($SELF --toggle-mode)" \
  --bind="ctrl-t:transform($SELF --toggle-open)" \
  --bind="alt-a:transform($SELF --toggle-sdk)" \
  --bind="alt-g:transform($SELF --toggle-group)" \
  --bind="alt-t:execute($SELF --tag-picker {+f})+reload($SELF --list-saved)" \
  --bind="ctrl-r:reload($SELF --refresh)" \
  --preview="$SELF --preview {1}" \
  --bind="ctrl-e:preview($SELF --preview {1} full)" \
  --preview-window='down,40%,wrap,border-top,follow,~4' \
  --bind='ctrl-/:change-preview-window(right,60%,wrap,border-left,follow,~4|down,40%,wrap,border-top,follow,~4)' \
  --bind='ctrl-y:transform:[ -n {1} ] && echo "execute-silent(printf %s {1} | pbcopy)+abort"' \
  --bind="alt-y:execute-silent($SELF --ids {*f} | pbcopy)+abort" \
  --bind="ctrl-o:execute($SELF --open-all {*f})+abort" \
  --bind="ctrl-x:execute($SELF --delete {+f})+clear-selection+reload($SELF --refresh)" \
  --bind='load:first+transform:[ -n {1} ] || echo down' \
  --bind="enter:transform:[ -n {1} ] && echo \"become($SELF --open-here {1})\""
