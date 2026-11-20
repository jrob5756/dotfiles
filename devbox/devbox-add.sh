# Sets up this Mac to SSH into Dev Boxes prepared with windows/devbox-ssh/setup.ps1 -Name <name>.
# Each box gets ~/.ssh/devboxes/<name>.conf (included by ~/.ssh/config) and a launchd agent,
# ~/Library/LaunchAgents/dotfiles.devtunnel.<name>.plist, that keeps devtunnel-forward running.
# The tunnel decides the port, so rerunning after setup.ps1 changes it picks up the new one.
# Env: DEVBOX_FORWARD (devtunnel-forward path), DEVTUNNEL (devtunnel CLI path),
#      DEVBOX_ADD_WAIT (seconds to wait for the agent to forward, default 45)

ssh_dir="$HOME/.ssh"
boxes="$ssh_dir/devboxes"
agents="$HOME/Library/LaunchAgents"
logs="$HOME/Library/Logs"
forward="${DEVBOX_FORWARD:?DEVBOX_FORWARD must name devtunnel-forward}"
domain="gui/$(id -u)"

die() { echo "devbox-add: $*" >&2; exit 1; }
label() { printf 'dotfiles.devtunnel.%s' "$1"; }
plist_path() { printf '%s/%s.plist' "$agents" "$(label "$1")"; }
conf_value() { awk -v key="$2" '$1 == key { print $2; exit }' "$1"; }
check_name() {
  [[ $1 =~ ^[a-z0-9][a-z0-9-]{1,58}[a-z0-9]$ ]] || die "invalid name '$1': use lowercase letters, digits and hyphens"
}
listening() { lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1; }

devtunnel_bin() {
  local found="${DEVTUNNEL:-}"
  [[ -n $found ]] || found="$(command -v devtunnel || true)"
  [[ -n $found ]] || found=/opt/homebrew/bin/devtunnel
  [[ -x $found ]] || die "devtunnel CLI not found; install it with: brew install --cask devtunnel"
  printf '%s' "$found"
}

usage() {
  cat <<'EOF'
Usage: devbox-add <name> [remote user]   add or update a Dev Box; the remote user is what
                                        `whoami` prints on the box (default: another box's)
       devbox-add --remove <name>       stop forwarding and forget the box
       devbox-add --list                boxes, their ports, and whether they are forwarding
Prepare the box first with: .\windows\devbox-ssh\setup.ps1 -Name <name> -Apply
EOF
}

list_boxes() {
  local conf name port agent
  shopt -s nullglob
  local confs=("$boxes"/*.conf)
  if ((${#confs[@]} == 0)); then
    echo "No Dev Boxes yet. Add one with: devbox-add <name>"
    return
  fi
  for conf in "${confs[@]}"; do
    name="$(basename "$conf" .conf)"
    port="$(conf_value "$conf" Port)"
    if launchctl print "$domain/$(label "$name")" >/dev/null 2>&1; then agent=loaded; else agent="not loaded"; fi
    if listening "$port"; then agent+=", forwarding"; else agent+=", not forwarding"; fi
    printf '%-24s port %-6s %s\n' "$name" "$port" "$agent"
  done
}

remove_box() {
  local name="$1"
  check_name "$name"
  launchctl bootout "$domain/$(label "$name")" 2>/dev/null || true
  rm -f "$(plist_path "$name")" "$boxes/$name.conf"
  ssh-keygen -R "$name" -f "$ssh_dir/known_hosts" >/dev/null 2>&1 || true
  echo "Removed $name. Its tunnel remains; on the box, setup.ps1 -Uninstall -Apply stops it, and"
  echo "devtunnel delete $name removes it."
}

write_plist() {
  local name="$1" devtunnel="$2" port="$3"
  cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<!-- Written by devbox-add (dotfiles); rerun it instead of editing. -->
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$(label "$name")</string>
  <key>ProgramArguments</key>
  <array>
    <string>$forward</string>
    <string>$devtunnel</string>
    <string>$name</string>
    <string>$port</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>ThrottleInterval</key>
  <integer>30</integer>
  <key>ProcessType</key>
  <string>Background</string>
  <key>StandardOutPath</key>
  <string>$logs/devtunnel-$name.log</string>
  <key>StandardErrorPath</key>
  <string>$logs/devtunnel-$name.log</string>
</dict>
</plist>
EOF
}

add_box() {
  local name="$1" user="${2:-}"
  check_name "$name"
  local devtunnel json ports port owner hosts conf other
  devtunnel="$(devtunnel_bin)"
  "$devtunnel" user show 2>&1 | grep -q 'Logged in as' || die "not signed in to dev tunnels; run: devtunnel user login"
  json="$("$devtunnel" show "$name" -j 2>/dev/null)" ||
    die "no tunnel named $name. On the Dev Box, run: .\\windows\\devbox-ssh\\setup.ps1 -Name $name -Apply"
  ports="$(jq -r '.tunnel.ports[]?.portNumber' <<<"$json")"
  [[ -n $ports && $ports != *$'\n'* ]] ||
    die "tunnel $name should have exactly one port, not '${ports//$'\n'/ }'; rerun setup.ps1 on the box"
  port="$ports"
  owner="$(jq -r '.tunnel.description // ""' <<<"$json" | sed -n 's/^SSH to //p')"
  hosts="$(jq -r '.tunnel.hostConnections // 0' <<<"$json")"

  conf="$boxes/$name.conf"
  shopt -s nullglob
  for other in "$boxes"/*.conf; do
    [[ $other == "$conf" ]] && continue
    if [[ $(conf_value "$other" Port) == "$port" ]]; then
      die "port $port is already used by $(basename "$other" .conf); rerun setup.ps1 on one of them with another -Port"
    fi
    [[ -n $user ]] || user="$(conf_value "$other" User)"
  done
  [[ -n $user || ! -f $conf ]] || user="$(conf_value "$conf" User)"
  [[ -n $user ]] || die "pass the remote user, as \`whoami\` prints it on the box: devbox-add $name 'DOMAIN\\user'"
  [[ -f $ssh_dir/id_ed25519 ]] ||
    echo "devbox-add: warning: no ~/.ssh/id_ed25519; create one and give setup.ps1 its .pub with -AuthorizedKeysFile" >&2

  mkdir -p "$boxes" "$agents" "$logs"
  chmod 700 "$ssh_dir" "$boxes"
  (
    umask 077
    printf '%s\n' "# Written by devbox-add (dotfiles); rerun it instead of editing." \
      "# Tunnel $name${owner:+ to $owner}, forwarded to localhost:$port by $(label "$name")." \
      "Host $name" "  HostName 127.0.0.1" "  Port $port" "  User $user" \
      "  IdentityFile ~/.ssh/id_ed25519" "  IdentitiesOnly yes" \
      "  # Every box listens on 127.0.0.1, so each keeps its host key under its own name." \
      "  HostKeyAlias $name" >"$conf"
  )
  write_plist "$name" "$devtunnel" "$port" >"$(plist_path "$name")"
  launchctl bootout "$domain/$(label "$name")" 2>/dev/null || true
  launchctl bootstrap "$domain" "$(plist_path "$name")"
  echo "Forwarding tunnel $name${owner:+ ($owner)} to localhost:$port."

  if [[ $hosts == 0 ]]; then
    echo "The tunnel has no host right now${owner:+; is $owner running}? The agent keeps retrying."
    return
  fi
  local i
  for ((i = 0; i < ${DEVBOX_ADD_WAIT:-45}; i++)); do listening "$port" && break; sleep 1; done
  local out
  if out="$(ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=20 "$name" hostname 2>&1)"; then
    echo "Ready: ssh $name reached $(tail -n 1 <<<"$out" | tr -d '\r')."
    echo "Host key: $(ssh-keygen -lF "$name" -f "$ssh_dir/known_hosts" 2>/dev/null | awk 'NF > 2 { print $3; exit }')"
    echo "It should match the fingerprint setup.ps1 printed on the box."
  elif grep -q 'REMOTE HOST IDENTIFICATION HAS CHANGED' <<<"$out"; then
    echo "$name answers with a different host key than before. If you rebuilt the box, forget the"
    echo "old key with: ssh-keygen -R $name, then rerun devbox-add $name."
    return 1
  else
    printf 'Could not log in yet:\n%s\n' "$out"
    echo "Check that your public key is in the box's authorized_keys (setup.ps1 -AuthorizedKeysFile)."
    return 1
  fi
}

case "${1:-}" in
  --list | -l) list_boxes ;;
  --remove | -r) [[ -n ${2:-} ]] || die "usage: devbox-add --remove <name>"; remove_box "$2" ;;
  "" | -h | --help) usage ;;
  -*) die "unknown option $1 (try --help)" ;;
  *) add_box "$@" ;;
esac
