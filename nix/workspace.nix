# Pure west workspace assembled from the committed lockfile.
#
# Replaces zmk-nix's fetchZephyrDeps fixed-output derivation: every project
# is fetched by pinned revision + content hash from nix/west.lock, so a
# changed config/west.yml can never silently reuse stale dependencies (the
# manifestHash assertion below fails eval instead), and the fetched sources
# are shared store paths across every firmware target.
{
  lib,
  fetchgit,
  runCommand,
  python3,
}:

let
  lock =
    if lib.pathExists ./west.lock then
      lib.importJSON ./west.lock
    else
      throw "nix/west.lock missing; run `nix run .#update` first";

  fetchProject =
    p:
    fetchgit {
      inherit (p) url;
      rev = p.revision;
      hash = p.hash;
      fetchSubmodules = p.submodules or false;
    };
in

assert lib.assertMsg (
  builtins.hashFile "sha256" ../config/west.yml == lock.manifestHash
) "config/west.yml changed since nix/west.lock was generated; run `nix run .#update`";

runCommand "zmk-west-workspace"
  {
    nativeBuildInputs = [ python3 ];
    passthru = { inherit lock; };
  }
  (
    lib.concatMapStrings (p: ''
      mkdir -p "$out/${p.path}"
      cp -r --no-preserve=mode ${fetchProject p}/. "$out/${p.path}/"
      python3 ${./make-fake-west-git.py} "$out/${p.path}" "${p.revision}"
    '') lock.projects
  )
