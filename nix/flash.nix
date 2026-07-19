# Per-keyboard UF2 flasher.
#
# Adapted from zmk-nix nix/flash.nix at
# f773db6782865905d064563a14e9e0b3f8d2d5f6. `parts` maps part name ->
# firmware derivation (single-image keyboards pass { "" = drv; }). The
# returned script flashes the named parts (all when none given) and exposes
# one single-part script per part via passthru, so `nix run
# .#flash.<kb>.<part>` has only that part's firmware in its closure.
#
# Detection: boards with the Adafruit nRF52 UF2 bootloader (xiao_ble,
# nice_nano) enumerate as block device model 'nRF UF2' in bootloader mode
# (verified on hardware for the XIAO nRF52840; label XIAO-SENSE).
{
  lib,
  writeShellApplication,
  util-linux,
  udisks2,
}:

let
  mkFlash =
    { name, parts }:
    let
      partNames = lib.attrNames parts;
    in
    writeShellApplication {
      name = "flash-${name}";

      runtimeInputs = [
        util-linux
        udisks2
      ];

      derivationArgs.passthru = lib.mapAttrs (
        part: drv:
        mkFlash {
          name = "${name}-${part}";
          parts = {
            ${part} = drv;
          };
        }
      ) parts;

      text = ''
        available() {
          lsblk -Sno path,model | grep -F 'nRF UF2' | cut -d' ' -f1
        }

        mounted() {
          findmnt "$device" -no target
        }

        uf2_for() {
          case "$1" in
        ${lib.concatMapStrings (part: ''
          ${lib.escapeShellArg part}) echo ${parts.${part}}/zmk.uf2 ;;
        '') partNames}
          esac
        }

        parts=(${lib.escapeShellArgs partNames})
        flash=("$@")

        if [ "''${#flash[@]}" -eq 0 ]; then
          flash=("''${parts[@]}")
        else
          for part in "''${flash[@]}"; do
            if ! printf '%s\0' "''${parts[@]}" | grep -Fxqz -- "$part"; then
              echo "error: unknown part '$part' for '${name}'; valid parts: ''${parts[*]}" >&2
              exit 1
            fi
          done
        fi

        for part in "''${flash[@]}"; do
          label="the keyboard"
          if [ -n "$part" ]; then
            label="the '$part' part of the keyboard"
          fi

          uf2="$(uf2_for "$part")"

          echo -n "Double tap reset and plug in $label via USB"
          while ! device="$(available)"; do
            echo -n .
            sleep 1
          done
          echo

          fslabel="$(lsblk -no label "$device" 2>/dev/null | tr -d '\n' || true)"
          echo "Found device at $device''${fslabel:+ (label: $fslabel)}"

          echo "We will now attempt to mount the device automatically using udisks every second."
          echo "Please either ensure that udisks is running or, alternatively, mount the device manually anywhere you prefer."
          echo -n "Waiting for mount "

          while ! mountpoint="$(mounted)"; do
            # Try to mount via udisks. If it works, we're good and the mountpoint
            # should be found in the next step. If not, it's either been auto-mounted
            # before we could which would also work out fine or it cannot be mounted
            # by udisks which would require the user to intervene manually in any
            # case.
            udisksctl mount --block-device "$device" >/dev/null 2>&1 && continue || echo -n .
            sleep 1
          done
          echo

          echo "Found mountpoint at $mountpoint"

          cp "$uf2" "$mountpoint"/
          sync

          echo -n "Firmware copied; waiting for the device to reboot"
          rebooted=0
          for _ in $(seq 15); do
            if ! available >/dev/null; then
              rebooted=1
              break
            fi
            echo -n .
            sleep 1
          done
          echo

          if [ "$rebooted" -eq 1 ]; then
            echo "flashed''${part:+ $part}"
          else
            echo "note: device still present after 15s; unmount and unplug it manually"
          fi
        done
      '';

      meta = {
        description = "ZMK UF2 firmware flasher (${name})";
        license = lib.licenses.mit;
        platforms = lib.platforms.linux;
      };
    };
in
mkFlash
