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
        skeletyl-dongle = {
          board = "xiao_ble";
          shield = "skeletyl_dongle";
        };
        skeletyl = {
          board = "nice_nano";
          shield = "skeletyl";
          split = true;
          flags = {
            CONFIG_ZMK_SPLIT_ROLE_CENTRAL = false;
          };
        };
        # skeletyl_left = {
        #   board = "nice_nano";
        #   shield = "skeletyl_left";
        #   flags = {
        #     CONFIG_ZMK_SPLIT = true;
        #     CONFIG_ZMK_SPLIT_ROLE_CENTRAL = false;
        #   };
        # };
        # skeletyl_right = {
        #   board = "nice_nano";
        #   shield = "skeletyl_right";
        #   flags = {
        #     CONFIG_ZMK_SPLIT = true;
        #     CONFIG_ZMK_SPLIT_ROLE_CENTRAL = false;
        #   };
        # };
      };

      mkKeyboardFirmware =
        name:
        {
          board,
          shield,
          split ? false,
          flags ? { },
          ...
        }@args:
        let
          builders = zmk-nix.legacyPackages.x86_64-linux;
          builder = if split then builders.buildSplitKeyboard else builders.buildKeyboard;
          shield = if split then "${args.shield}_%PART%" else args.shield;
          extraCmakeFlags = lib.mapAttrsToList (key: value: "-D${key}=${if value then "y" else "n"}") flags;
        in
        builder {
          inherit
            name
            board
            shield
            extraCmakeFlags
            ;
          src = ./.;
          config = "config";
          zephyrDepsHash = "sha256-otsUf6aEeOmAUOV76YNXaYANAIhDWX+mm4ye8GoJ7WM=";
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
          default = firmwarePackages.skeletyl_dongle;
          firmware = firmwarePackages.skeletyl_dongle;

          keyboards = firmwarePackages;
          flash = flashPackages;
          update = zmk-nix.packages.update.x86_64-linux.update;
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
