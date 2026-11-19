# prefix A: a popup dashboard of live Copilot CLI agents, from the @agent_state
# and @agent_session that tmux-agent-status sets: state, name, where, how long
# it has been working or idle, premium requests, and what it is doing. The
# preview shows the pane live; enter jumps there, ctrl-r refreshes.
# Usage: tmux-agent-dashboard [client]   (internal: --list, --jump <pane> <client>)
STATE="${COPILOT_HOME:-$HOME/.copilot}/session-state"
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
us=$'\x1f'
E=$'\033['
R="${E}0m"; DIM="${E}38;2;127;132;156m"; TXT="${E}38;2;205;214;244m"; BOLD="${E}1m"

color() {
  case $1 in
    input) printf '%s' "${E}38;2;250;179;135m" ;;
    error) printf '%s' "${E}38;2;243;139;168m" ;;
    working) printf '%s' "${E}38;2;249;226;175m" ;;
    done) printf '%s' "${E}38;2;166;227;161m" ;;
    *) printf '%s' "$DIM" ;;
  esac
}
symbol() { case $1 in input) echo '?' ;; error) echo '✗' ;; working) echo '●' ;; done) echo '✓' ;; *) echo '○' ;; esac; }
label() { case $1 in input) echo 'needs you' ;; error) echo 'error' ;; working) echo 'working' ;; done) echo 'done' ;; *) echo 'idle' ;; esac; }
rank() { case $1 in input) echo 1 ;; error) echo 2 ;; working) echo 3 ;; done) echo 4 ;; *) echo 5 ;; esac; }

ago() {
  local s=$1
  if [ "$s" -lt 60 ]; then echo "${s}s"
  elif [ "$s" -lt 3600 ]; then echo "$((s / 60))m"
  elif [ "$s" -lt 86400 ]; then echo "$((s / 3600))h$(( (s % 3600) / 60 ))m"
  else echo "$((s / 86400))d"
  fi
}

# "activity<US>since<US>requests" for a session: what it is doing now, when the
# current interaction (or idle spell) started, and premium requests so far.
details() {
  local log="$STATE/$1/events.jsonl" state=$2
  [ -f "$log" ] || { printf '%s%s%s' "" "$us" "$us"; return; }
  tail -n 400 "$log" | grep -vF '},"agentId":"' | jq -r -s --arg state "$state" '
    def ts: (.timestamp // "") | sub("\\.[0-9]+Z$"; "Z") | (try fromdate catch null);
    def short: tostring | gsub("\\s+"; " ") | ltrimstr(" ") | .[0:160];
    (map(select(.type == "user.message")) | last) as $prompt
    | (map(select(.type == "tool.execution_start" or .type == "assistant.message"
                  or .type == "user.message" or .type == "human_response.recorded")) | last) as $act
    | (map(select(.type == "session.usage_checkpoint")) | last | .data.totalPremiumRequests // "") as $req
    | (if $state == "input" then
         (map(select(.type == "tool.execution_start" and .data.toolName == "ask_user")) | last
          | "asks: " + ((.data.arguments.message // .data.arguments.question // "a question") | short))
       elif $act == null then ""
       elif $act.type == "tool.execution_start" then
         ($act.data.toolTitle // $act.data.toolName) + ": "
           + (($act.data.arguments.description // $act.data.arguments.command // $act.data.arguments.path
               // $act.data.arguments.pattern // $act.data.arguments.query // "") | short)
       elif $act.type == "assistant.message" then ($act.data.content // "" | short)
       else "thinking about: " + ($prompt.data.content // "" | short) end) as $what
    | (if $state == "working" or $state == "input" then ($prompt | ts) else (last | ts) end) as $since
    | [$what, ($since // "" | tostring), ($req | tostring)] | join("\u001f")' 2>/dev/null ||
    printf '%s%s%s' "" "$us" "$us"
}

list() {
  local now; now=$(date +%s)
  local rows=()
  while IFS=$us read -r pane state sid where title; do
    [ -n "$state" ] && [ -n "$sid" ] || continue
    local name="${title% - GitHub Copilot}"
    [ "$name" = "$title" ] || [ "$name" = "GitHub Copilot" ] && name=""
    [ -n "$name" ] || name=$(awk '/^name: / { sub(/^name: */, ""); gsub(/^["\047]|["\047]$/, ""); print; exit }' "$STATE/$sid/workspace.yaml" 2>/dev/null)
    [ -n "$name" ] || name=${sid:0:8}
    local what since req
    IFS=$us read -r what since req <<<"$(details "$sid" "$state")"
    local dur=""
    [ -n "$since" ] && dur=$(ago $((now - since)))
    [ -n "$req" ] && req="$req req"
    rows+=("$(rank "$state")$us$pane$us$(color "$state")$(symbol "$state") $(printf '%-9s' "$(label "$state")")$R $BOLD$TXT$(printf '%-38.38s' "$name")$R $DIM$(printf '%-22.22s' "$where")$R $(printf '%6s' "$dur")  $DIM$(printf '%9s' "$req")$R  $TXT$what$R")
  done < <(tmux list-panes -a -F "#{pane_id}$us#{@agent_state}$us#{@agent_session}$us#{session_name}:#{window_index} #{window_name}$us#{pane_title}")
  printf '%s\n' "${rows[@]}" | sort -t "$us" -k1,1n | cut -d "$us" -f2-
}

case "${1:-}" in
  --list) list; exit ;;
  --jump)
    [ -n "${3:-}" ] && tmux switch-client -c "$3" -t "$2"
    tmux select-window -t "$2" \; select-pane -t "$2"
    exit ;;
esac

client="${1:-}"
[[ $client == *"#{"* ]] && client=$(tmux display -p "#{client_name}" 2>/dev/null || true)
# fzf expands $FZF_PREVIEW_LINES when it runs the preview.
# shellcheck disable=SC2016
list | fzf --ansi --no-sort --height=100% --layout=reverse --delimiter="$us" --with-nth=2 \
  --prompt='agents › ' --info=inline-right \
  --header=$'state      name                                   where                   time   requests  doing\nenter jump · ctrl-r refresh · esc close' \
  --preview='tmux capture-pane -ep -t {1} | tail -n "$FZF_PREVIEW_LINES"' \
  --preview-window='down,55%,border-top' \
  --bind="ctrl-r:reload($SELF --list)" \
  --bind="enter:become($SELF --jump {1} '$client')"
