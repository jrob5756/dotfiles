# Keep shared functions compatible with both Bash and Zsh.
_copilot_bin() {
    if command -v copilot >/dev/null 2>&1; then
        command -v copilot
        return 0
    fi
    python3 - "$HOME/.copilot-cli" <<'PY'
import os
from pathlib import Path
import re
import sys

try:
    binaries = [
        directory / "copilot"
        for directory in Path(sys.argv[1]).iterdir()
        if directory.is_dir()
        and (directory / "copilot").is_file()
        and os.access(directory / "copilot", os.X_OK)
    ]
except FileNotFoundError:
    sys.exit(1)
except OSError as exc:
    print(f"cup: cannot inspect {sys.argv[1]}: {exc}", file=sys.stderr)
    sys.exit(1)
if not binaries:
    sys.exit(1)

def version_key(binary):
    return tuple(
        (1, int(part)) if part.isdecimal() else (0, part)
        for part in re.split(r"(\d+)", binary.parent.name)
        if part
    )

print(max(binaries, key=version_key))
PY
}

_dotfiles_copilot() {
    local copilot_bin
    if ! copilot_bin=$(_copilot_bin); then
        echo "copilot: CLI not found on PATH or in ~/.copilot-cli" >&2
        return 1
    fi
    env -u TMUX "$copilot_bin" "$@"
}

# Emit "<name>\t<path>" for every directory-sourced marketplace in settings.json.
_copilot_local_marketplaces() {
    python3 - "$1" <<'PY'
import json
from pathlib import Path
import re
import sys

try:
    text = Path(sys.argv[1]).read_text(encoding="utf-8")
except FileNotFoundError:
    sys.exit(0)
except (OSError, UnicodeError) as exc:
    print(f"cup: cannot read {sys.argv[1]}: {exc}", file=sys.stderr)
    sys.exit(1)

# Accept whole-line comments in otherwise valid JSON.
text = re.sub(r'^\s*//.*$', '', text, flags=re.MULTILINE)
try:
    data = json.loads(text)
    if not isinstance(data, dict):
        raise ValueError("settings must be an object")
    marketplaces = data.get("extraKnownMarketplaces")
    if marketplaces is None:
        marketplaces = {}
    if not isinstance(marketplaces, dict):
        raise ValueError("extraKnownMarketplaces must be an object")
    records = []
    for name, entry in marketplaces.items():
        if not isinstance(entry, dict):
            raise ValueError(f"marketplace {name!r} must be an object")
        source = entry.get("source", {})
        if not isinstance(source, dict):
            raise ValueError(f"marketplace {name!r} source must be an object")
        if source.get("source") != "directory":
            continue
        path = source.get("path")
        if not isinstance(path, str) or not path:
            raise ValueError(f"marketplace {name!r} needs a nonempty directory path")
        if not name or any(char in name or char in path for char in "\0\t\r\n"):
            raise ValueError("marketplace names and paths must be nonempty and contain no NUL, tabs, or line breaks")
        records.append((name, path))
except ValueError as exc:
    print(f"cup: cannot parse {sys.argv[1]}: {exc}", file=sys.stderr)
    sys.exit(1)
for name, path in records:
    print(f"{name}\t{path}")
PY
}

# Continue independent updates, but return failure if any update was incomplete.
cup() {
    local tool
    for tool in python3 git; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            printf 'cup: %s is required\n' "$tool" >&2
            return 1
        fi
    done

    local copilot_bin
    if ! copilot_bin=$(_copilot_bin); then
        echo "cup: copilot CLI not found on PATH or in ~/.copilot-cli" >&2
        return 1
    fi

    local settings="${COPILOT_CONFIG_DIR:-$HOME/.copilot}/settings.json"
    local marketplaces
    if ! marketplaces=$(_copilot_local_marketplaces "$settings"); then
        return 1
    fi

    local marketplace_name marketplace_path worktree repo_status failed=0
    if [[ -n $marketplaces ]]; then
        while IFS=$'\t' read -r marketplace_name marketplace_path; do
            case "$marketplace_path" in
                "~") marketplace_path=$HOME ;;
                "~/"*) marketplace_path="$HOME/${marketplace_path#\~/}" ;;
            esac
            if [[ ! -d $marketplace_path ]]; then
                echo "cup: $marketplace_name -> $marketplace_path does not exist, skipping pull" >&2
                failed=1
            elif ! worktree=$(git -C "$marketplace_path" rev-parse --is-inside-work-tree) || [[ $worktree != true ]]; then
                echo "cup: $marketplace_name -> $marketplace_path is not a usable Git worktree, skipping pull" >&2
                failed=1
            elif ! repo_status=$(git -C "$marketplace_path" status --porcelain); then
                echo "cup: cannot inspect $marketplace_name, skipping pull" >&2
                failed=1
            elif [[ -n $repo_status ]]; then
                echo "cup: $marketplace_name -> $marketplace_path has uncommitted changes, skipping pull" >&2
                failed=1
            else
                echo "cup: pulling $marketplace_name ($marketplace_path)"
                if ! git -C "$marketplace_path" pull --ff-only; then
                    echo "cup: pull failed for $marketplace_name" >&2
                    failed=1
                fi
            fi
        done <<EOF
$marketplaces
EOF
    else
        echo "cup: no directory marketplaces found in $settings" >&2
    fi

    if ! "$copilot_bin" plugin marketplace update; then
        echo "cup: marketplace catalog update failed" >&2
        failed=1
    fi

    local update_out
    if update_out=$("$copilot_bin" plugin update --all 2>&1); then
        [[ $update_out == "No plugins installed."* ]] || printf '%s\n' "$update_out"
    else
        printf 'cup: plugin update failed\n%s\n' "$update_out" >&2
        failed=1
    fi
    return "$failed"
}
