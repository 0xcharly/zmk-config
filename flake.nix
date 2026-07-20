{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs =
    { nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      inherit (nixpkgs) lib;

      zmk = import ./nix { inherit pkgs; };

      configSrc = lib.fileset.toSource {
        root = ./.;
        fileset = ./config;
      };

      # A keyboard is either a single image { board, shield, ... } or a set of
      # parts { parts.<part> = { board, shield, ... }; }. Each part of a
      # multi-part keyboard declares its split role with exactly one of
      # `central = true` / `peripheral = true` (validated below); the role is
      # compiled as CONFIG_ZMK_SPLIT_ROLE_CENTRAL=y/n.
      keyboards = {
        reset-xiao_ble = {
          board = "xiao_ble//zmk";
          shield = "settings_reset";
        };
        reset-nice_nano = {
          board = "nice_nano//zmk";
          shield = "settings_reset";
        };
        skeletyl.parts = {
          dongle = {
            board = "xiao_ble//zmk";
            shield = "skeletyl_studio prospector_adapter";
            studio = true;
            central = true;
          };
          left = {
            board = "nice_nano//zmk";
            shield = "skeletyl_studio_left";
            peripheral = true;
          };
          right = {
            board = "nice_nano//zmk";
            shield = "skeletyl_studio_right";
            peripheral = true;
          };
        };
        cygnus.parts = {
          dongle = {
            board = "xiao_ble//zmk";
            shield = "cygnus_studio prospector_adapter";
            central = true;
            studio = true;
          };
          left = {
            board = "nice_nano//zmk";
            shield = "cygnus_studio_left";
            peripheral = true;
          };
          right = {
            board = "nice_nano//zmk";
            shield = "cygnus_studio_right";
            peripheral = true;
          };
        };
      };

      mkFirmware =
        name: spec:
        if spec ? parts then
          let
            # Role validation: each part sets exactly one of central/peripheral;
            # the role key CONFIG_ZMK_SPLIT_ROLE_CENTRAL must not be set by
            # hand; exactly one central part per keyboard.
            checkedParts = lib.mapAttrs (
              part: pspec:
              let
                central = pspec.central or false;
                peripheral = pspec.peripheral or false;
              in
              assert lib.assertMsg (
                central != peripheral
              ) "keyboard '${name}': part '${part}' must set exactly one of central = true / peripheral = true";
              assert lib.assertMsg (!((pspec.flags or { }) ? CONFIG_ZMK_SPLIT_ROLE_CENTRAL))
                "keyboard '${name}': part '${part}' sets flags.CONFIG_ZMK_SPLIT_ROLE_CENTRAL directly; use central/peripheral instead";
              (removeAttrs pspec [
                "central"
                "peripheral"
              ])
              // {
                flags = (pspec.flags or { }) // {
                  CONFIG_ZMK_SPLIT_ROLE_CENTRAL = central;
                };
              }
            ) spec.parts;
            centralParts = lib.attrNames (lib.filterAttrs (_: p: p.central or false) spec.parts);
            parts =
              assert lib.assertMsg (lib.length centralParts == 1)
                "keyboard '${name}': exactly one part must set central = true (found: ${
                  if centralParts == [ ] then "none" else lib.concatStringsSep ", " centralParts
                })";
              lib.mapAttrs (
                part: pspec:
                zmk.buildFirmware (
                  pspec
                  // {
                    name = "${name}-${part}";
                    src = configSrc;
                  }
                )
              ) checkedParts;
          in
          pkgs.runCommand name
            {
              passthru = parts // {
                inherit parts;
              };
            }
            ''
              mkdir $out
              ${lib.concatStrings (
                lib.mapAttrsToList (part: drv: "ln -s ${drv}/zmk.uf2 $out/${name}-${part}.uf2\n") parts
              )}
            ''
        else
          assert lib.assertMsg (
            !(spec ? central) && !(spec ? peripheral)
          ) "keyboard '${name}': central/peripheral only apply to parts of a multi-part keyboard";
          zmk.buildFirmware (
            spec
            // {
              inherit name;
              src = configSrc;
            }
          );

      mkFlash =
        name: firmware:
        zmk.mkFlash {
          inherit name;
          parts = firmware.parts or { "" = firmware; };
        };

      firmwarePackages = lib.mapAttrs mkFirmware keyboards;
    in
    {
      packages.${system} = {
        default = firmwarePackages.skeletyl;
        firmware = firmwarePackages;
        flash = lib.mapAttrs mkFlash firmwarePackages;
        update = zmk.update;
      };

      devShells.${system}.default = zmk.shell;
    };
}
