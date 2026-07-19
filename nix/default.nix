{ pkgs }:
rec {
  workspace = pkgs.callPackage ./workspace.nix { };
  buildFirmware = pkgs.callPackage ./firmware.nix { inherit workspace; };
  mkFlash = pkgs.callPackage ./flash.nix { };
  update = pkgs.callPackage ./update.nix { };
  shell = pkgs.callPackage ./shell.nix { };
}
