# Development shell. Toolchain/python set vendored from zmk-nix
# nix/shell.nix at f773db6782865905d064563a14e9e0b3f8d2d5f6, plus local
# editing/debugging tools.
{
  mkShell,
  cmake,
  gcc-arm-embedded,
  ninja,
  protobuf,
  python3,
  nixd,
  nixfmt,
  prettierd,
  usbutils,
}:

mkShell {
  packages = [
    cmake
    ninja
    (python3.withPackages (ps: [
      # From https://github.com/zmkfirmware/zephyr/blob/HEAD/scripts/requirements-base.txt
      ps.west
      ps.pyelftools
      ps.pyyaml
      ps.pykwalify
      ps.canopen
      ps.packaging
      ps.progress
      ps.psutil
      ps.pylink-square
      ps.pyserial
      ps.requests
      ps.anytree
      ps.intelhex
      # For ZMK Studio builds
      ps.protobuf
      ps.grpcio-tools
    ]))
    gcc-arm-embedded
    protobuf

    # Editing tools.
    nixd
    nixfmt
    prettierd

    # USB debugging (lsusb).
    usbutils
  ];

  env = {
    ZEPHYR_TOOLCHAIN_VARIANT = "gnuarmemb";
    GNUARMEMB_TOOLCHAIN_PATH = gcc-arm-embedded;
  };
}
