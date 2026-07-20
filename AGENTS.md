# AGENTS.md

ZMK firmware config for split keyboards (skeletyl, cygnus) with a vendored
Nix build framework under `nix/`. No external ZMK/Zephyr flake inputs —
`nixpkgs` is the only input.

## Layout

- `flake.nix` — the `keyboards` attrset is the single source of truth for
  what gets built. Single-image keyboards are `{ board, shield }`;
  multi-part keyboards are `parts.<part> = { board, shield, central |
  peripheral, studio?, flags? }`.
- `config/` — ZMK config: `west.yml` (manifest), keymaps, and local shields
  under `config/boards/shields/`. This is the ONLY directory that firmware
  builds see (`configSrc` = fileset of `./config`); edits to README, draw/,
  etc. never invalidate builds.
- `nix/west.lock` — generated JSON (despite the extension). Pins every west
  project (name, url, 40-hex revision, path, SRI hash, submodules) plus
  `manifestHash` = sha256 of `config/west.yml`. Committed. NEVER hand-edit;
  regenerate with `nix run .#update`.
- `nix/workspace.nix` — assembles the shared `zmk-west-workspace` from the
  lock via per-repo `fetchgit`; asserts `manifestHash` at eval time.
- `nix/make-fake-west-git.py` — synthesizes minimal `.git` dirs so west
  resolves manifest `import:`s offline. Deterministic; picks the
  *shallowest* `west.yml` in each project.
- `nix/firmware.nix` — single-image builder (west build --cmake-only +
  ninja, `gnuarmemb` toolchain).
- `nix/flash.nix` — flasher; detects Adafruit nRF52 UF2 bootloaders by
  lsblk model `nRF UF2`.
- `nix/update.nix` — lock generator (network; runs unsandboxed via
  `nix run`).
- `draw/` — keymap drawing config; unrelated to the build pipeline.

## Commands

```sh
nix build .#firmware.<kb>            # all parts (result/<kb>-<part>.uf2)
nix build .#firmware.<kb>.<part>     # one part only (result/zmk.uf2)
nix run .#flash.<kb>                 # flash all parts in sequence
nix run .#flash.<kb>.<part>          # flash one part; closure contains only
                                     # that part's firmware
nix run .#flash.<kb> -- <part>...    # subset by argument
nix run .#update                     # regenerate nix/west.lock (network)
nix develop                          # toolchain + nixd/nixfmt/prettierd/lsusb
```

Keyboards: `skeletyl`, `skeletyl-prospector` (skeletyl + prospector dongle
screen), `cygnus` (parts `dongle`, `left`, `right`), `reset-xiao_ble`,
`reset-nice_nano` (single-image settings_reset).

## Invariants — do not break

- `config/west.yml` and `nix/west.lock` move together. Editing the manifest
  without relocking fails every firmware eval with an explicit message;
  that failure is the design, not a bug. Fix: `nix run .#update`, commit
  both files.
- Each part of a multi-part keyboard sets exactly one of `central = true` /
  `peripheral = true`, and exactly one part per keyboard is central.
  `flags.CONFIG_ZMK_SPLIT_ROLE_CENTRAL` must never be set by hand. All
  three rules are eval-time assertions in `flake.nix`.
- `flags` attrset: bools compile to `-DCONFIG_*=y/n`, strings pass through
  verbatim (e.g. `flags.CONFIG_BT_MAX_CONN = "6"`).
- Per-part caching is intentional: a change to one part's spec must not
  rebuild sibling parts. If a refactor makes `skeletyl.left` rebuild when
  only the dongle spec changed, the refactor is wrong.
- All west sources come from the one `zmk-west-workspace` derivation.
  Adding a second fetch path (FODs, `builtins.fetchGit`, per-package
  fetches) reintroduces the bugs this design removed.

## Repo conventions

- jj-managed, always git-colocated (`.git` exists; `git rev-parse
  --show-toplevel` is safe). Flake evaluation only sees git-TRACKED files:
  after creating a file that Nix must read, `git add` it or eval fails with
  "path ... is not tracked".
- Format Nix with `nixfmt` (in the devshell). Formatting must not change
  any drvPath.
- Shields provided by west projects (e.g. `prospector_adapter`,
  `settings_reset`) are referenced by name in shield strings; only local
  shields live under `config/boards/shields/`.
- `result` symlinks are build artifacts; never commit or read them as
  source of truth.

## Verification recipes

- Eval sanity (fast, no builds): `nix eval .#firmware.<kb>.drvPath`.
- Smoke build: `nix build .#firmware.reset-nice_nano` (~1 min warm) →
  non-empty `result/zmk.uf2`.
- Flash script without hardware: `nix run .#flash.<kb> -- bogus` must list
  valid parts; running with no device prints the wait prompt (Ctrl-C).
  CAUTION: if a board in bootloader mode is plugged in, the script WILL
  mount and flash it — check `lsblk -Sno path,model` for `nRF UF2` first.
- Lock idempotence: a second `nix run .#update` prints `unchanged` and
  leaves the file byte-identical.
- After touching `nix/*.nix`, confirm an untouched target's drvPath is
  unchanged unless the change is meant to affect it.

## Known constraints

- Toolchain is `ZEPHYR_TOOLCHAIN_VARIANT=gnuarmemb` + nixpkgs
  `gcc-arm-embedded`. If a future Zephyr drops gnuarmemb, switch
  `nix/firmware.nix` and `nix/shell.nix` to
  `ZEPHYR_TOOLCHAIN_VARIANT=cross-compile` +
  `CROSS_COMPILE=${gcc-arm-embedded}/bin/arm-none-eabi-`.
- `nix run .#update` needs network and takes minutes (full `west update`
  into a tmpdir); unchanged projects reuse hashes so relocks after a
  comment-only manifest edit are cheap.
- Locked SHAs must stay reachable upstream; a force-push that GCs one makes
  `fetchgit` fail loudly → re-pin with `nix run .#update`.
