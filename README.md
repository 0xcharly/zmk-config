# Keymaps

## Build

```sh
nix build .#firmware.<keyboard>
```

## flash

```sh
nix run .#flash.<keyboard>
```

# Troubleshooting

To force refetch the Zephyr dependencies, clear out `zephyrDepsHash`.
