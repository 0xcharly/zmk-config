# Single-image ZMK firmware builder.
#
# Merged from zmk-nix nix/zephyr/builder.nix + nix/zmk/keyboard.nix at
# f773db6782865905d064563a14e9e0b3f8d2d5f6, with dependency provisioning
# swapped from a per-package fixed-output `west update` to the shared,
# lock-pinned workspace derivation (see nix/workspace.nix).
{
  lib,
  stdenv,
  workspace,
  cmake,
  ninja,
  gcc-arm-embedded,
  git,
  python3,
  protobuf,
}:

{
  name, # "skeletyl-dongle"
  board, # "xiao_ble//zmk"
  shield ? null, # "skeletyl_dongle prospector_adapter"
  studio ? false,
  flags ? { }, # CONFIG_* attrset: bool -> y/n, string passed through
  extraCmakeFlags ? [ ],
  src, # config source tree
}:

let
  westBuildFlags = [
    "-s"
    "zmk/app"
    "-b"
    board
  ]
  ++ lib.optionals studio [
    "-S"
    "studio-rpc-usb-uart"
  ]
  ++ [ "--" ]
  ++ lib.optional (shield != null) "-DSHIELD=${shield}"
  ++ lib.optional studio "-DCONFIG_ZMK_STUDIO=y"
  ++ lib.mapAttrsToList (
    k: v: "-D${k}=${if lib.isBool v then (if v then "y" else "n") else toString v}"
  ) flags
  ++ extraCmakeFlags;
in

stdenv.mkDerivation {
  inherit name src;

  nativeBuildInputs = [
    cmake
    git
    ninja
    python3.pythonOnBuildForHost.pkgs.west
    python3.pythonOnBuildForHost.pkgs.pyelftools
  ]
  ++ lib.optionals studio [
    protobuf
    python3.pythonOnBuildForHost.pkgs.protobuf
    python3.pythonOnBuildForHost.pkgs.grpcio-tools
  ];

  env = {
    ZEPHYR_TOOLCHAIN_VARIANT = "gnuarmemb";
    GNUARMEMB_TOOLCHAIN_PATH = "${gcc-arm-embedded}";
  };

  configurePhase = ''
    declare -ag westBuildFlagsArray=(${lib.escapeShellArgs westBuildFlags})

    runHook preConfigure

    cp --no-preserve=mode -rt . ${workspace}/*

    mkdir -p .west
    cat >.west/config <<EOF
    [manifest]
    path = config
    file = west.yml
    EOF

    westBuildFlagsArray+=("-DZMK_CONFIG=$(readlink -f config)")

    if zephyrRoot="$(dirname "$(dirname "$(find "$(pwd)" -path '*/share/zephyr-package/cmake' -printf '%h' -quit)")")"; then
      addCMakeParams "$zephyrRoot"
      westBuildFlagsArray+=("-DBUILD_VERSION=$(<"$zephyrRoot"/.git/HEAD)")
    fi

    west build -d "''${cmakeBuildDir:=build}" --cmake-only "''${westBuildFlagsArray[@]}"

    cd "$cmakeBuildDir"

    runHook postConfigure
  '';

  postConfigure = ''
    if [ -d ../modules/lib/nanopb/generator ]; then
      chmod +x ../modules/lib/nanopb/generator/{nanopb_generator,protoc,protoc-gen-nanopb}
      patchShebangs ../modules/lib/nanopb/generator
    fi
  '';

  installPhase = ''
    runHook preInstall

    install -Dm444 zephyr/zmk.uf2 $out/zmk.uf2

    runHook postInstall
  '';

  passthru = { inherit board shield; };

  meta = {
    description = "ZMK firmware (${name})";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
