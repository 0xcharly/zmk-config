# Lockfile generator: resolves config/west.yml (west init + west update in a
# scratch dir, network access via `nix run`) and writes nix/west.lock with
# per-project pinned revisions and fetchgit-compatible SRI hashes. Hashes of
# unchanged projects are reused from the existing lock, so routine updates
# only prefetch what actually moved.
{
  writeShellApplication,
  coreutils,
  git,
  jq,
  nix,
  nix-prefetch-git,
  python3,
}:

writeShellApplication {
  name = "zmk-west-update";

  runtimeInputs = [
    coreutils
    git
    jq
    nix
    nix-prefetch-git
    (python3.withPackages (ps: [
      ps.west
      ps.pyelftools
    ]))
  ];

  text = ''
    export NIX_CONFIG='extra-experimental-features = nix-command flakes'

    root="''${1:-$(git rev-parse --show-toplevel)}"

    if [ ! -f "$root/config/west.yml" ]; then
      echo "error: $root/config/west.yml not found; run from the zmk-config repo or pass its root as \$1" >&2
      exit 1
    fi

    oldlock="$root/nix/west.lock"

    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT

    cp -r "$root/config" "$tmp/config"
    cd "$tmp"
    west init -l config
    west update

    entries=()
    changes=()

    while IFS='|' read -r name path url; do
      if [ "$name" = manifest ]; then
        continue
      fi

      rev="$(git -C "$tmp/$path" rev-parse HEAD)"

      submodules=false
      if [ -s "$tmp/$path/.gitmodules" ]; then
        submodules=true
      fi

      hash=""
      oldrev=""
      if [ -f "$oldlock" ]; then
        oldrev="$(jq -r --arg name "$name" \
          '[.projects[] | select(.name == $name)][0].revision // ""' "$oldlock")"
        hash="$(jq -r --arg name "$name" --arg url "$url" --arg rev "$rev" --argjson sub "$submodules" \
          '[.projects[] | select(.name == $name and .url == $url and .revision == $rev and (.submodules // false) == $sub)][0].hash // ""' \
          "$oldlock")"
      fi

      if [ -z "$hash" ]; then
        echo "prefetching $name ($rev)..." >&2
        prefetch_args=(--rev "$rev")
        if [ "$submodules" = true ]; then
          prefetch_args+=(--fetch-submodules)
        fi
        hash="$(nix-prefetch-git "file://$tmp/$path" "''${prefetch_args[@]}" 2>/dev/null | jq -r .hash)"
      fi

      if [ -z "$oldrev" ]; then
        changes+=("$name: new at $rev")
      elif [ "$oldrev" != "$rev" ]; then
        changes+=("$name: $oldrev -> $rev")
      fi

      entries+=("$(jq -n \
        --arg name "$name" --arg url "$url" --arg rev "$rev" \
        --arg path "$path" --arg hash "$hash" --argjson sub "$submodules" \
        '{name: $name, url: $url, revision: $rev, path: $path, hash: $hash, submodules: $sub}')")
    done < <(west list -f '{name}|{path}|{url}')

    manifestHash="$(nix hash file --type sha256 --base16 "$root/config/west.yml")"

    printf '%s\n' "''${entries[@]}" | jq -s --arg manifestHash "$manifestHash" \
      '{manifestHash: $manifestHash, projects: sort_by(.name)}' \
      > "$root/nix/west.lock"

    if [ "''${#changes[@]}" -eq 0 ]; then
      echo "unchanged"
    else
      printf '%s\n' "''${changes[@]}"
    fi
  '';

  meta.description = "Regenerate nix/west.lock from config/west.yml";
}
