# Tags tmux panes and windows with the state of the Copilot CLI agents in them.
#   pane   @agent_state  working | input | error | done | idle
#          @agent_session the session the pane shows
#   window @agent        the most urgent pane state: input > error > working > done
#          @agent_<state> how many panes are in each of those states (unset if none)
#          @agent_seen   when the window was last viewed (epoch seconds)
#   global @agents_<state> how many agents are in each state across all
#                          sessions, including idle (unset if none)
# "done" means the agent finished after you last viewed its window, so viewing
# the window clears it. Runs from status-right as #(tmux-agent-status) and on
# window switches.

state_dir="${COPILOT_HOME:-$HOME/.copilot}/session-state"
# lsof reports resolved paths (macOS's /tmp is /private/tmp).
state_dir=$(cd "$state_dir" 2>/dev/null && pwd -P || echo "$state_dir")
title_suffix=" - GitHub Copilot"
now=$(date +%s)

# Candidates are any process whose command line mentions copilot (npm installs
# run as node); only those holding a session file below count.
pids=$(ps -Ao pid=,command= | awk '/copilot/ && !/copilot-runtime/ { print $1 }' | paste -sd, -)

# "pid<TAB>session id" for every session a copilot process has open: an open
# session's process holds <session>/inuse.<pid>.hold, and stale files left by
# crashed processes aren't held by anything.
held=""
if [ -n "$pids" ]; then
  held=$(lsof -nP -a -p "$pids" -Fpn 2>/dev/null | awk -v state="$state_dir/" '
    /^p/ { p = substr($0, 2); next }
    /^n/ && index($0, state) == 2 && $0 ~ /\/inuse\.[0-9]+\.hold$/ {
      n = substr($0, 2 + length(state)); split(n, a, "/"); print p "\t" a[1] }' | sort -u || true)
fi

mtime() { date -r "$1" +%s 2>/dev/null || echo 0; }

# Whether a session is waiting on background shells or agents: an interaction
# that ends while they run looks finished in the log until their completion
# notification starts the next turn. Tracks the IDs that tool results report as
# backgrounded until a notification, stop_bash or read reports them done. Reads
# a bounded tail since logs grow to ~100 MB; subagents' own work is excluded.
waiting() {
  tail -c 4000000 "$1" |
    grep -E '^\{"type":"(tool\.execution_complete|system\.notification|session\.(start|resume|shutdown))"' |
    grep -vF '},"agentId":"' |
    awk '
      function track(re, group, add,   m) {
        if (match($0, re, m)) {
          if (add) pending[m[group]] = 1
          else delete pending[m[group]]
        }
      }
      /^\{"type":"session\./ { delete pending; next }
      {
        # Detached shells are long-lived services nobody waits on.
        track("\"content\":\"<command started in background with shellId: ([^>\"]+)>\"", 1, 1)
        # A sync shell that timed out or that the user moved to the background.
        track("<command with shellId: ([^ \"\\\\]+) [^\"\\\\]*>\"", 1, 1)
        track("\"content\":\"[^\"]{0,20}(started in background with agent_id: |moved to background \\(agent_id: )([^.,) \"]+)", 2, 1)
        track("\"content\":\"Message delivered to agent ([^. \"]+)\\.", 1, 1)
        track("\"content\":\"Agent [^\"]*agent_id: ([^,\"]+), agent_type: [^,\"]*, status: running", 1, 1)
        track("<shellId: ([^ \"]+) completed with exit code -?[0-9]+>\"", 1, 0)
        track("\"content\":\"<command with id: ([^ \"]+) stopped>\"", 1, 0)
        track("\"content\":\"Agent [^\"]*agent_id: ([^,\"]+), agent_type: [^,\"]*, status: (idle|completed|failed|cancelled)", 1, 0)
        track("\"kind\":\\{\"type\":\"(shell_completed|agent_idle|agent_completed)\",\"(shellId|agentId)\":\"([^\"]+)\"", 3, 0)
      }
      END { exit length(pending) == 0 }'
}

# A session's state from the tail of its event log. An interaction ends with
# assistant.turn_end then session.usage_checkpoint; a bare turn_end is only the
# gap between two model turns unless nothing follows for a while. An agent
# waiting on background shells or agents counts as working.
session_state() {
  local log="$state_dir/$1/events.jsonl" state
  [ -f "$log" ] || { echo idle; return; }
  state=$(tail -n 300 "$log" | awk -v age="$((now - $(mtime "$log")))" '
    { t = $0; sub(/^\{"type":"/, "", t); sub(/".*/, "", t) }
    t == "tool.execution_start" && /"toolName":"ask_user"/ { ask = 1; last = "working"; next }
    t == "human_response.recorded" || (t == "tool.execution_complete" && ask) { ask = 0 }
    t == "permission.requested" { perm = 1 }
    t == "permission.completed" { perm = 0 }
    t ~ /^(session\.(usage_checkpoint|task_complete|start|resume|shutdown)|abort)$/ { last = "idle"; next }
    t == "assistant.turn_end" { last = "turn_end"; next }
    t == "session.error" || t == "model.turn_failed" { last = "error"; next }
    t ~ /^(user\.message|assistant\.|tool\.execution|model\.|subagent\.|hook\.|session\.compaction_start)/ { last = "working" }
    END {
      if (ask || perm) print "input"
      else if (last == "turn_end") print (age > 10) ? "idle" : "working"
      else print (last == "") ? "idle" : last
    }')
  if [ "$state" = idle ] && waiting "$log"; then
    state=working
  fi
  echo "$state"
}

session_name() {
  local file="$state_dir/$1/workspace.yaml"
  [ -f "$file" ] || return 0
  awk '/^name: / { sub(/^name: */, ""); gsub(/^["\047]|["\047]$/, ""); print; exit }' "$file"
}

rank() {
  case $1 in
    input) echo 4 ;;
    error) echo 3 ;;
    working) echo 2 ;;
    done) echo 1 ;;
    *) echo 0 ;;
  esac
}

declare -A tty_pids=() pane_state=() pane_session=() win_state=() win_count=() win_seen=() total=()
if [ -n "$pids" ]; then
  while read -r pid tty; do
    [ "$tty" = "??" ] || tty_pids[$tty]+="$pid "
  done < <(ps -o pid=,tty= -p "$pids" 2>/dev/null || true)
fi

us=$'\x1f' # not whitespace, so empty fields don't collapse
while IFS=$us read -r pane pane_tty window active attached seen title; do
  tty=${pane_tty#/dev/}
  [ -n "${tty_pids[$tty]:-}" ] || continue
  read -r -a tty_pid_list <<<"${tty_pids[$tty]}"
  ids=()
  for pid in "${tty_pid_list[@]}"; do
    while IFS=$'\t' read -r holder id; do
      [ "$holder" = "$pid" ] && ids+=("$id")
    done <<<"$held"
  done
  [ "${#ids[@]}" -gt 0 ] || continue

  # A process can hold sessions it isn't showing (the sidebar). The shown one
  # is named in the pane title; failing that, take the most recently written.
  shown="" newest=-1
  for id in "${ids[@]}"; do
    if [[ $title == *"$title_suffix" && "$(session_name "$id")" == "${title%"$title_suffix"}" ]]; then
      shown=$id
      break
    fi
    written=$(mtime "$state_dir/$id/events.jsonl")
    if [ "$written" -gt "$newest" ]; then
      newest=$written
      shown=$id
    fi
  done
  state=$(session_state "$shown")

  looking=0
  [ "$active" = 1 ] && [ "$attached" != 0 ] && looking=1
  if [ "$looking" = 1 ] || [ -z "$seen" ]; then
    seen=$now
    win_seen[$window]=$now
  fi
  if [ "$state" = idle ] && [ "$looking" = 0 ] && [ "$(mtime "$state_dir/$shown/events.jsonl")" -gt "$seen" ]; then
    state="done"
  fi

  pane_state[$pane]=$state
  pane_session[$pane]=$shown
  total[$state]=$((${total[$state]:-0} + 1))
  win_count[$window:$state]=$((${win_count[$window:$state]:-0} + 1))
  if [ "$(rank "$state")" -gt "$(rank "${win_state[$window]:-}")" ]; then
    win_state[$window]=$state
  fi
done < <(tmux list-panes -a -F "#{pane_id}$us#{pane_tty}$us#{window_id}$us#{window_active}$us#{session_attached}$us#{@agent_seen}$us#{pane_title}")

commands=()
while read -r pane; do
  if [ -n "${pane_state[$pane]:-}" ]; then
    commands+=(set -p -t "$pane" @agent_state "${pane_state[$pane]}" \; set -p -t "$pane" @agent_session "${pane_session[$pane]}" \;)
  else
    commands+=(set -pu -t "$pane" @agent_state \; set -pu -t "$pane" @agent_session \;)
  fi
done < <(tmux list-panes -a -F '#{pane_id}')
while read -r window; do
  if [ -n "${win_seen[$window]:-}" ]; then
    commands+=(set -w -t "$window" @agent_seen "${win_seen[$window]}" \;)
  fi
  if [ "$(rank "${win_state[$window]:-}")" -gt 0 ]; then
    commands+=(set -w -t "$window" @agent "${win_state[$window]}" \;)
  else
    commands+=(set -wu -t "$window" @agent \;)
  fi
  for state in input error working "done"; do
    if [ -n "${win_count[$window:$state]:-}" ]; then
      commands+=(set -w -t "$window" "@agent_$state" "${win_count[$window:$state]}" \;)
    else
      commands+=(set -wu -t "$window" "@agent_$state" \;)
    fi
  done
done < <(tmux list-windows -a -F '#{window_id}')
for state in input error working "done" idle; do
  if [ -n "${total[$state]:-}" ]; then
    commands+=(set -g "@agents_$state" "${total[$state]}" \;)
  else
    commands+=(set -gu "@agents_$state" \;)
  fi
done
# Option changes alone don't redraw the status line.
while read -r client; do
  commands+=(refresh-client -S -t "$client" \;)
done < <(tmux list-clients -F '#{client_name}' 2>/dev/null)
[ "${#commands[@]}" -eq 0 ] || tmux "${commands[@]}" >/dev/null 2>&1 || true
