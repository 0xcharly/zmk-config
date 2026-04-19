{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

    zmk-nix = {
      url = "github:lilyinstarlight/zmk-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { nixpkgs, zmk-nix, ... }:
    let
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      inherit (nixpkgs) lib;

      keyboards = {
        reset-xiao_ble = {
          board = "xiao_ble//zmk";
          shield = "settings_reset";
        };
        reset-nice_nano = {
          board = "nice_nano//zmk";
          shield = "settings_reset";
        };
        skeletyl-dongle = {
          board = "xiao_ble//zmk";
          shield = "skeletyl_dongle prospector_adapter";
        };
        skeletyl = {
          board = "nice_nano//zmk";
          shield = "skeletyl";
          split = true;
          flags.CONFIG_ZMK_SPLIT_ROLE_CENTRAL = false;
        };
        cygnus-dongle = {
          board = "xiao_ble//zmk";
          shield = "cygnus_studio prospector_adapter";
          studio = true;
        };
        cygnus = {
          board = "nice_nano//zmk";
          shield = "cygnus_studio";
          split = true;
          flags.CONFIG_ZMK_SPLIT_ROLE_CENTRAL = false;
        };
      };

      mkKeyboardFirmware =
        name:
        {
          board,
          shield,
          split ? false,
          studio ? false,
          flags ? { },
          ...
        }:
        let
          builders = zmk-nix.legacyPackages.x86_64-linux;
          builder = if split then builders.buildSplitKeyboard else builders.buildKeyboard;
        in
        builder {
          inherit name board;
          shield = if split then "${shield}_%PART%" else shield;
          enableZmkStudio = studio;
          extraCmakeFlags = lib.mapAttrsToList (key: value: "-D${key}=${if value then "y" else "n"}") flags;

          src = ./.;
          config = "config";
          zephyrDepsHash = "sha256-74BIbxnUW7qZqug3hLfg7+wD8vRs39mnE6ER9mZWuAI=";
          meta = with lib; {
            description = "ZMK firmware for ${name}";
            license = licenses.mit;
            platforms = platforms.all;
          };
        };
    in
    {
      packages.x86_64-linux =
        let
          firmwarePackages = lib.mapAttrs mkKeyboardFirmware keyboards;
          flashPackages = lib.mapAttrs (
            _: firmware: zmk-nix.packages.x86_64-linux.flash.override { inherit firmware; }
          ) firmwarePackages;
        in
        {
          default = firmwarePackages.cygnus-dongle;
          firmware = firmwarePackages;
          flash = flashPackages;
          update = zmk-nix.packages.x86_64-linux.update;
        };

      devShells.x86_64-linux.default = zmk-nix.devShells.x86_64-linux.default.overrideAttrs (old: {
        buildInputs = old.buildInputs ++ [
          # Editing tools.
          pkgs.nixd
          pkgs.nixfmt
          pkgs.prettierd
        ];
      });
    };
}
