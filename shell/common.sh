# Shell functions shared by bash and zsh.
#
# Sourced from modules/shell.nix rather than duplicated per shell, which is what
# let the bash and zsh copies of `cup` drift apart before the Nix migration.
# Keep everything here portable between bash and zsh: no `shopt`, no zsh-only
# parameter expansions such as ${var:A} or ${var:t}.

# Agency installs the Copilot CLI as ~/.copilot-cli/<version>/copilot and puts
# no shim on PATH, so resolve the highest installed version at call time.
_copilot_bin() {
    if command -v copilot >/dev/null 2>&1; then
        command -v copilot
        return 0
    fi
    local latest
    latest=$(ls -1 "$HOME/.copilot-cli" 2>/dev/null | sort -V | tail -n 1)
    [[ -n $latest && -x "$HOME/.copilot-cli/$latest/copilot" ]] || return 1
    printf '%s\n' "$HOME/.copilot-cli/$latest/copilot"
}

# Emit "<name>\t<path>" for every directory-sourced marketplace in settings.json.
_copilot_local_marketplaces() {
    python3 - "$1" <<'PY'
import json, re, sys

try:
    text = open(sys.argv[1], encoding="utf-8").read()
except OSError:
    sys.exit(0)
# settings.json is sometimes written with // line comments.
text = re.sub(r'^\s*//.*$', '', text, flags=re.MULTILINE)
try:
    data = json.loads(text)
except ValueError as exc:
    print(f"cup: cannot parse {sys.argv[1]}: {exc}", file=sys.stderr)
    sys.exit(1)
for name, entry in (data.get("extraKnownMarketplaces") or {}).items():
    source = (entry or {}).get("source") or {}
    if source.get("source") == "directory" and source.get("path"):
        print(f"{name}\t{source['path']}")
PY
}

# cup: refresh every locally-sourced copilot plugin marketplace.
#
# The @jason-tools / @conductor / @conductor-workflows plugins come from
# "directory" marketplaces, so the CLI loads them straight off disk and never
# records them under `copilot plugin list` / ~/.copilot/installed-plugins.
# Updating them therefore means pulling the backing git repo, then asking the
# CLI to re-read each marketplace catalog.
cup() {
    local copilot_bin
    if ! copilot_bin=$(_copilot_bin); then
        echo "cup: copilot CLI not found on PATH or in ~/.copilot-cli" >&2
        return 1
    fi

    local settings="${COPILOT_CONFIG_DIR:-$HOME/.copilot}/settings.json"
    local name path found=0
    while IFS=$'\t' read -r name path; do
        [[ -n $name && -n $path ]] || continue
        found=1
        path="${path/#\~/$HOME}"
        if [[ ! -d $path ]]; then
            echo "cup: $name -> $path does not exist, skipping" >&2
        elif [[ ! -d $path/.git ]]; then
            echo "cup: $name -> $path is not a git repo, nothing to pull"
        elif [[ -n $(git -C "$path" status --porcelain) ]]; then
            echo "cup: $name -> $path has uncommitted changes, skipping pull" >&2
        else
            echo "cup: pulling $name ($path)"
            git -C "$path" pull --ff-only || echo "cup: pull failed for $name" >&2
        fi
    done < <(_copilot_local_marketplaces "$settings")

    (( found )) || echo "cup: no directory marketplaces found in $settings" >&2

    "$copilot_bin" plugin marketplace update
    # Covers any genuinely installed (non-directory) plugins. With only
    # directory marketplaces this is a no-op, so don't print its noise.
    local update_out
    update_out=$("$copilot_bin" plugin update --all 2>&1)
    [[ $update_out == "No plugins installed."* ]] || printf '%s\n' "$update_out"
}

# `dev [dir]` — open (or switch to) a per-directory tmux dev session.
#
# One session per path: reuses the session if one already exists for that
# directory, otherwise creates it with the dev layout (nvim left ~70% + the `a`
# copilot alias right ~30%). Works from inside or outside tmux. The session is
# named dev-<basename>, so two different dirs sharing a basename collide — rare
# enough to accept for readability in `tmux ls`.
#
# `a` and `nvim` are launched via send-keys because `a` is a shell alias: it only
# resolves inside an interactive shell that sourced the rc files, whereas a
# split-window command would run via `sh -c` and never see it.
dev() {
    local dir name base
    dir=$(cd "${1:-$PWD}" 2>/dev/null && pwd -P) || {
        echo "dev: no such directory: ${1:-$PWD}" >&2
        return 1
    }
    base="${dir##*/}"
    [[ -n $base ]] || base="root"
    # tmux treats . and : as session-name syntax, so fold anything else to _.
    name=$(printf 'dev-%s' "$base" | tr -c '[:alnum:]_-' '_')

    if ! tmux has-session -t "=${name}" 2>/dev/null; then
        tmux new-session -d -s "$name" -c "$dir"
        tmux split-window -h -l 30% -t "$name" -c "$dir"
        tmux send-keys -t "$name" a C-m
        tmux select-pane -t "$name" -L
        tmux send-keys -t "$name" nvim C-m
    fi

    if [[ -n $TMUX ]]; then
        tmux switch-client -t "$name"
    else
        tmux attach-session -t "$name"
    fi
}
