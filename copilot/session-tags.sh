#!/usr/bin/env bash
# Tag Copilot CLI sessions. Tags live outside Copilot's own files, keyed by
# session id, so they survive renames and never touch a running CLI.
# Usage: session-tags <command> [args]
#   add [-s id]... tag...      tag sessions (default: $COPILOT_AGENT_SESSION_ID)
#   rm  [-s id]... tag...      untag sessions
#   ls  [-s id]                a session's tags, one per line
#   all                        every tag with its session count, most used first
#   forget id...               drop all tags of these sessions
#   gc                         drop tags of sessions that no longer exist
#   window [-n] [-t tag] [window]
#                              tag every session open in a tmux window
#                              (default tag: the window name; -n: dry run)
#   migrate-prefixes [-n]      turn "prefix_Name" session names into the tag
#                              "prefix" and strip it from names of sessions
#                              that aren't loaded anywhere (-n: dry run)
# Tags are lowercased; a leading "#" is dropped; allowed: a-z 0-9 . _ / -
# Env: SESSION_TAGS_DB (default $XDG_STATE_HOME/session-browser/tags.db)
set -euo pipefail

COPILOT_DIR="${COPILOT_HOME:-$HOME/.copilot}"
STATE="$COPILOT_DIR/session-state"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/session-browser"
DB="${SESSION_TAGS_DB:-$STATE_DIR/tags.db}"
BROWSER="$(command -v session-browser || true)"

die() { echo "session-tags: $*" >&2; exit 1; }

sql() {
  mkdir -p "$(dirname "$DB")"
  sqlite3 -cmd ".timeout 3000" "$DB" \
    "CREATE TABLE IF NOT EXISTS session_tags (
       session_id TEXT NOT NULL,
       tag        TEXT NOT NULL,
       created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
       PRIMARY KEY (session_id, tag)) WITHOUT ROWID;
     CREATE INDEX IF NOT EXISTS session_tags_by_tag ON session_tags(tag);" "$@"
}

norm_tag() {  # prints the normalized tag or fails
  local t; t="$(printf '%s' "${1#\#}" | tr '[:upper:]' '[:lower:]')"
  [[ "$t" =~ ^[a-z0-9][a-z0-9._/-]{0,39}$ ]] || return 1
  printf '%s' "$t"
}
check_id() { [[ "$1" =~ ^[A-Za-z0-9-]+$ ]] || die "not a session id: $1"; }

# Parses "-s id" options into IDS and the remaining args into TAGS.
parse_targets() {
  IDS=(); TAGS=()
  while (( $# )); do
    case "$1" in
      -s) [[ $# -ge 2 ]] || die "-s needs a session id"; check_id "$2"; IDS+=("$2"); shift 2 ;;
      *)  TAGS+=("$1"); shift ;;
    esac
  done
  if (( ${#IDS[@]} == 0 )); then
    [[ -n "${COPILOT_AGENT_SESSION_ID:-}" ]] || die "no session: pass -s <id> or run inside a Copilot session"
    check_id "$COPILOT_AGENT_SESSION_ID"; IDS=("$COPILOT_AGENT_SESSION_ID")
  fi
}

norm_tags() {  # normalizes TAGS in place
  local -a out=(); local t n
  for t in "${TAGS[@]+"${TAGS[@]}"}"; do
    n="$(norm_tag "$t")" || die "invalid tag: $t (allowed: a-z 0-9 . _ / -, up to 40 chars)"
    out+=("$n")
  done
  (( ${#out[@]} )) || die "no tags given"
  TAGS=("${out[@]}")
}

values() {  # "('id','tag'),..." for every id in IDS × tag argument
  local out="" id tag
  for id in "${IDS[@]}"; do for tag in "$@"; do out+="${out:+,}('$id','$tag')"; done; done
  printf '%s' "$out"
}

# A session's display name from its workspace.yaml (single- or double-quoted or plain).
session_name() {
  awk '/^name: / { v = substr($0, 7)
         if (v ~ /^\047/) { v = substr(v, 2, length(v) - 2); gsub(/\047\047/, "\047", v) }
         else if (v ~ /^"/) { v = substr(v, 2, length(v) - 2); gsub(/\\"/, "\"", v); gsub(/\\\\/, "\\", v) }
         print v; exit }' "$STATE/$1/workspace.yaml" 2>/dev/null
}

cmd_window() {
  local dry=0 tag="" opt
  OPTIND=1
  while getopts ":nt:" opt; do
    case "$opt" in
      n) dry=1 ;;
      t) tag="$OPTARG" ;;
      *) die "usage: window [-n] [-t tag] [window]" ;;
    esac
  done
  shift $((OPTIND - 1))
  local target="${1:-${TMUX_PANE:-}}"
  [[ -n "$target" ]] || die "not inside tmux: pass a window, e.g. window notes-teams"
  local loc wname
  loc="$(tmux display-message -p -t "$target" '#{session_name}:#{window_index}')"
  wname="$(tmux display-message -p -t "$target" '#{window_name}')"
  [[ -n "$tag" ]] || tag="$(printf '%s' "$wname" | tr '[:upper:] ' '[:lower:]-')"
  local norm; norm="$(norm_tag "$tag")" || die "\"$tag\" isn't a valid tag; pass -t <tag>"
  tag="$norm"

  [[ -x "$BROWSER" ]] || die "session-browser not found on PATH"
  local -a ids=()
  local id
  while IFS= read -r id; do [[ -n "$id" ]] && ids+=("$id"); done < <(
    "$BROWSER" --inuse | awk -F'\t' -v w="tmux $loc." '$2 == "open" && index($3, w) { print $1 }')
  if (( ${#ids[@]} == 0 )); then echo "No Copilot sessions open in window $loc ($wname)."; return 0; fi

  local verb=tagged; (( dry )) && verb="would tag"
  for id in "${ids[@]}"; do printf '  %s #%s  %s\n' "$verb" "$tag" "$(session_name "$id")"; done
  (( dry )) && return 0
  IDS=("${ids[@]}")
  sql "INSERT OR IGNORE INTO session_tags(session_id, tag) VALUES $(values "$tag");"
}

cmd_migrate() {
  local dry=0
  [[ "${1:-}" == -n ]] && dry=1
  [[ -x "$BROWSER" ]] || die "session-browser not found on PATH"
  # Sessions loaded by any copilot process: their workspace.yaml would be rewritten.
  local held; held=" $("$BROWSER" --inuse | cut -f1 | tr '\n' ' ') "

  # id <TAB> tag <TAB> old name <TAB> new name, for names like "proofs_Some title".
  local plan f id n t
  plan="$(for f in "$STATE"/*/workspace.yaml; do
      id="${f%/workspace.yaml}"; id="${id##*/}"
      # Names with backslashes (YAML escapes) are left alone rather than re-quoted.
      grep -q '^name: .*\\' "$f" && continue
      n="$(session_name "$id")"
      [[ "$n" =~ ^([A-Za-z0-9][A-Za-z0-9.-]{0,30})_(.+)$ ]] || continue
      t="$(norm_tag "${BASH_REMATCH[1]}")" || continue
      printf '%s\t%s\t%s\t%s\n' "$id" "$t" "$n" "${BASH_REMATCH[2]}"
    done | sort -t$'\t' -k2,2 -k3,3)"
  if [[ -z "$plan" ]]; then echo "No prefixed session names found."; return 0; fi

  local tag old new prev="" renamed=0 kept=0
  while IFS=$'\t' read -r id tag old new; do
    if [[ "$tag" != "$prev" ]]; then printf '\n#%s\n' "$tag"; prev="$tag"; fi
    if [[ "$held" == *" $id "* ]]; then
      printf '  %s  (open: tag only; re-run once it is closed to rename)\n' "$old"; kept=$((kept + 1))
    else
      printf '  %s  →  %s\n' "$old" "$new"; renamed=$((renamed + 1))
    fi
  done <<<"$plan"
  printf '\n%d session(s): %d to tag and rename, %d open (tag only).\n' "$((renamed + kept))" "$renamed" "$kept"
  if (( dry )); then echo "Dry run: nothing changed."; return 0; fi

  local backup; backup="$STATE_DIR/backups/names-$(date +%Y%m%d-%H%M%S).tar.gz"
  mkdir -p "$(dirname "$backup")"
  cut -f1 <<<"$plan" | sed 's|$|/workspace.yaml|' | tar -czf "$backup" -C "$STATE" -T -
  echo "Backed up their workspace.yaml files to $backup"

  local vals=""
  while IFS=$'\t' read -r id tag old new; do vals+="${vals:+,}('$id','$tag')"; done <<<"$plan"
  sql "INSERT OR IGNORE INTO session_tags(session_id, tag) VALUES $vals;"

  while IFS=$'\t' read -r id tag old new; do
    [[ "$held" == *" $id "* ]] && continue
    f="$STATE/$id/workspace.yaml"
    # Passed via the environment: awk -v would expand backslash escapes.
    NAME_LINE="name: '${new//\'/\'\'}'" awk '!done && /^name: / { print ENVIRON["NAME_LINE"]; done = 1; next } { print }' "$f" > "$f.tags.$$" &&
      mv -f "$f.tags.$$" "$f"
  done <<<"$plan"
  echo "Done."
}

cmd="${1:-}"; shift || true
case "$cmd" in
  add)
    parse_targets "$@"; norm_tags
    sql "INSERT OR IGNORE INTO session_tags(session_id, tag) VALUES $(values "${TAGS[@]}");" ;;
  rm)
    parse_targets "$@"; norm_tags
    sql "DELETE FROM session_tags WHERE (session_id, tag) IN (VALUES $(values "${TAGS[@]}"));" ;;
  ls)
    parse_targets "$@"
    [[ -f "$DB" ]] || exit 0
    sql "SELECT tag FROM session_tags WHERE session_id = '${IDS[0]}' ORDER BY tag;" ;;
  all)
    [[ -f "$DB" ]] || exit 0
    sql -separator $'\t' "SELECT tag, count(*) FROM session_tags GROUP BY tag ORDER BY count(*) DESC, tag;" ;;
  forget)
    (( $# )) && [[ -f "$DB" ]] || exit 0
    ids=""; for id in "$@"; do check_id "$id"; ids+="${ids:+,}'$id'"; done
    sql "DELETE FROM session_tags WHERE session_id IN ($ids);" ;;
  gc)
    [[ -f "$DB" ]] || exit 0
    live="$(ls "$STATE" 2>/dev/null | grep -E '^[A-Za-z0-9-]+$' | sed "s/.*/('&')/" | paste -sd, - || true)"
    [[ -n "$live" ]] || exit 0  # never wipe everything because the state dir looks empty
    sql "CREATE TEMP TABLE live(id TEXT PRIMARY KEY); INSERT OR IGNORE INTO live VALUES $live;
         DELETE FROM session_tags WHERE session_id NOT IN (SELECT id FROM live);" ;;
  window)           cmd_window "$@" ;;
  migrate-prefixes) cmd_migrate "$@" ;;
  ""|-h|--help)     sed -n '2,/^set -euo/p' "$0" | sed '$d; s/^# \{0,1\}//' ;;
  *)                die "unknown command: $cmd (try --help)" ;;
esac
