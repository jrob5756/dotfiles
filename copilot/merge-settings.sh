# Merges the given JSON object into Copilot CLI's settings.json, one level deep
# (e.g. {"statusLine": {...}} replaces only the keys it names inside statusLine).
# Copilot owns the rest of the file and rewrites it at runtime, so it can't be a
# read-only Home Manager link. Rewrites the file only when something changes.
# Usage: copilot-merge-settings '<json object>'
patch="$1"
dir="${COPILOT_HOME:-$HOME/.copilot}"
file="$dir/settings.json"
mkdir -p "$dir"
[[ -s "$file" ]] || printf '{}\n' > "$file"

if ! merged="$(jq --argjson patch "$patch" '
    reduce ($patch | to_entries[]) as $e (.;
      .[$e.key] = (if (.[$e.key] | type) == "object" and ($e.value | type) == "object"
                   then .[$e.key] + $e.value else $e.value end))' "$file")"; then
  echo "copilot-merge-settings: $file isn't valid JSON; left it unchanged" >&2
  exit 0
fi
if [[ "$(jq -S . "$file")" == "$(jq -S . <<<"$merged")" ]]; then exit 0; fi

tmp="$(mktemp "$file.XXXXXX")"
printf '%s\n' "$merged" > "$tmp"
chmod 600 "$tmp"
mv -f "$tmp" "$file"
echo "copilot-merge-settings: updated $file"
