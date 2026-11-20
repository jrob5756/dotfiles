# Keeps `devtunnel connect <tunnel>` forwarding a Dev Box's sshd to localhost:<port>.
# Usage: devtunnel-forward <devtunnel> <tunnel> <port>
#
# devtunnel connect can stay up while forwarding nothing (relay errors such as "Not
# authorized", or a 404 while the box sleeps), so launchd's KeepAlive alone never
# restarts it. This wrapper exits once the client stops forwarding: when it exits, when
# it isn't listening on <port>, or when nothing answers there with an SSH banner. launchd
# then starts a fresh one.
# Env: DEVTUNNEL_FORWARD_INTERVAL (seconds between checks, default 30),
#      DEVTUNNEL_FORWARD_GRACE (seconds before the first check, default 30),
#      DEVTUNNEL_FORWARD_MISSES (failed checks before restarting, default 3)

if (($# != 3)); then
  echo "usage: devtunnel-forward <devtunnel> <tunnel> <port>" >&2
  exit 2
fi
devtunnel=$1 tunnel=$2 port=$3
interval=${DEVTUNNEL_FORWARD_INTERVAL:-30}
grace=${DEVTUNNEL_FORWARD_GRACE:-30}
max_misses=${DEVTUNNEL_FORWARD_MISSES:-3}

log() { echo "$(date '+%Y-%m-%dT%H:%M:%S') devtunnel-forward $tunnel: $*"; }

"$devtunnel" connect "$tunnel" &
child=$!
trap 'kill "$child" 2>/dev/null' EXIT
trap 'exit 0' TERM INT

# Our client, not some other process, listens on the port, and an sshd answers through it.
forwarding() {
  lsof -nP -a -p "$child" -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1 || return 1
  local banner=""
  { exec 3<>"/dev/tcp/127.0.0.1/$port"; } 2>/dev/null || return 1
  IFS= read -r -t 10 banner <&3 || true
  exec 3<&-
  [[ $banner == SSH-* ]]
}

sleep "$grace" &
wait $!
misses=0
while kill -0 "$child" 2>/dev/null; do
  if forwarding; then
    misses=0
  else
    misses=$((misses + 1))
    if ((misses >= max_misses)); then
      log "not forwarding port $port after $misses checks; restarting"
      exit 1
    fi
  fi
  sleep "$interval" &
  wait $!
done
status=0
wait "$child" || status=$?
log "devtunnel connect exited ($status); restarting"
exit 1
