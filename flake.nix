{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
    nixpkgs-darwin.url = "github:NixOS/nixpkgs/nixpkgs-24.05-darwin";

    # Version of requirements.txt installed in pythonEnv
    zephyr = {
      url = "github:zephyrproject-rtos/zephyr/v3.5.0";
      flake = false;
    };

    # Zephyr sdk and toolchain
    zephyr-nix = {
      url = "github:urob/zephyr-nix";
      inputs = {
        zephyr.follows = "zephyr";
        nixpkgs.follows = "nixpkgs";
      };
    };
    zephyr-nix-darwin = {
      url = "github:urob/zephyr-nix";
      inputs = {
        zephyr.follows = "zephyr";
        nixpkgs.follows = "nixpkgs-darwin";
      };
    };
  };

  outputs = {
    nixpkgs,
    nixpkgs-darwin,
    zephyr-nix,
    zephyr-nix-darwin,
    ...
  }: let
    systems = ["x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin"];
    forAllSystems = nixpkgs.lib.genAttrs systems;
  in {
    devShells = forAllSystems (system: let
      pkgs =
        if (system == "x86_64-darwin" || system == "aarch64-darwin")
        then nixpkgs-darwin.legacyPackages.${system}
        else nixpkgs.legacyPackages.${system};
      zephyr =
        if (system == "x86_64-darwin" || system == "aarch64-darwin")
        then zephyr-nix-darwin.packages.${system}
        else zephyr-nix.packages.${system};
      keymap_drawer = pkgs.python3Packages.callPackage ./draw {};
    in {
      default = pkgs.mkShell {
        packages = [
          # Editing tools.
          pkgs.nixd
          pkgs.alejandra
          pkgs.prettierd

          # ZMK.
          keymap_drawer

          zephyr.pythonEnv
          (zephyr.sdk.override {targets = ["arm-zephyr-eabi"];})

          pkgs.cmake
          pkgs.dtc
          pkgs.ninja
          pkgs.qemu # needed for native_posix target

          pkgs.gawk # awk
          pkgs.unixtools.column # column
          pkgs.coreutils # cp, cut, echo, mkdir, sort, tail, tee, uniq, wc
          pkgs.diffutils # diff
          pkgs.findutils # find, xargs
          pkgs.gnugrep # grep
          pkgs.just # just
          pkgs.gnused # sed
          pkgs.yq # yq
        ];
      };
    });
  };
}
