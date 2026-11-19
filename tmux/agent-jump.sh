# Jumps to the next Copilot CLI agent that needs attention: waiting on you,
# then errored, then finished (the @agent_state tmux-agent-status sets).
# Repeated presses cycle through them. Usage: tmux-agent-jump [client]
client="${1:-}"
us=$'\x1f' # not whitespace, so empty fields don't collapse

rank() {
  case $1 in
    input) echo 1 ;;
    error) echo 2 ;;
    done) echo 3 ;;
    *) echo 0 ;;
  esac
}

current=$(tmux display -p ${client:+-c "$client"} '#{pane_id}')
targets=()
while IFS=$us read -r state session window pane id; do
  r=$(rank "$state")
  [ "$r" -eq 0 ] || targets+=("$r$us$session$us$(printf '%05d%05d' "$window" "$pane")$us$id")
done < <(tmux list-panes -a -F "#{@agent_state}$us#{session_name}$us#{window_index}$us#{pane_index}$us#{pane_id}")

if [ "${#targets[@]}" -eq 0 ]; then
  tmux display ${client:+-c "$client"} 'No agents need you'
  exit 0
fi

mapfile -t ordered < <(printf '%s\n' "${targets[@]}" | sort -t "$us" -k1,1n -k2,2 -k3,3 | awk -F "$us" '{ print $4 }')
next=${ordered[0]}
for i in "${!ordered[@]}"; do
  if [ "${ordered[i]}" = "$current" ]; then
    next=${ordered[(i + 1) % ${#ordered[@]}]}
    break
  fi
done
if [ -n "$client" ]; then
  tmux switch-client -c "$client" -t "$next"
fi
tmux select-window -t "$next" \; select-pane -t "$next"
