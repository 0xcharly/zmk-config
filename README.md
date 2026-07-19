# Keymaps

## Build

```sh
nix build .#firmware.<keyboard>
```

Multi-part keyboards (`skeletyl`, `cygnus`) produce one `.uf2` per part
(`dongle`, `left`, `right`); a single part builds with
`nix build .#firmware.<keyboard>.<part>`.

## Flash

Flash every part in sequence:

```sh
nix run .#flash.<keyboard>
```

Flash a single part (only that part's firmware is built):

```sh
nix run .#flash.<keyboard>.<part>
# or
nix run .#flash.<keyboard> -- <part>...
```

## Update dependencies

West dependencies are pinned in `nix/west.lock`. After editing
`config/west.yml` (or to pick up new commits on the tracked branches):

```sh
nix run .#update
```

then commit `config/west.yml` and `nix/west.lock` together. A stale lock
fails the build at evaluation time with a message pointing back here.
