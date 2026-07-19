"""Synthesize a minimal fake .git directory for a west project.

Usage: make-fake-west-git.py <project_dir> <head_sha>

At build time west resolves manifest `import:`s (e.g. zmk's `import:
app/west.yml`) from each project's git `manifest-rev` ref, not from the
worktree, and considers a project "cloned" only if `.git` exists. The
sources assembled by nix/workspace.nix come from fetchgit, which strips
`.git`, so we recreate just enough of one:

- a deterministic commit (zlib level 0, epoch-0 author/committer) holding a
  single-file tree with the project's west.yml, referenced by
  `refs/heads/manifest-rev` -- or, when the project has no west.yml, the
  (dangling) pinned revision, which west tolerates for import-less projects;
- `HEAD` containing the pinned revision (the firmware builder reads
  `zephyr/.git/HEAD` for -DBUILD_VERSION).

Adapted from lilyinstarlight/zmk-nix nix/zephyr/fetcher.nix
(make-fake-west-git) at f773db6782865905d064563a14e9e0b3f8d2d5f6.
"""

import hashlib
import os
import os.path
import sys
import zlib


def init_repo(git_dir):
    os.makedirs(os.path.join(git_dir, 'refs/heads'), exist_ok=True)
    os.makedirs(os.path.join(git_dir, 'objects'), exist_ok=True)


def write_object(git_dir, object_type, contents):
    object_raw = object_type.encode() + b' ' + \
                 str(len(contents)).encode() + b'\x00' + contents
    object_hash = hashlib.sha1(object_raw).hexdigest()

    object_path = os.path.join(git_dir,
                               'objects', object_hash[:2], object_hash[2:])

    os.makedirs(os.path.dirname(object_path), exist_ok=True)

    with open(object_path, 'wb') as object_file:
        object_file.write(zlib.compress(object_raw, 0))

    return object_hash


def write_single_file_tree(git_dir, file_path, base_path):
    tree_file = file_path.removeprefix(base_path).removeprefix('/')

    tree = None
    for part in sorted(tree_file.split(os.path.sep), reverse=True):
        if tree:
            contents = b'40000 ' + part.encode() + b'\x00' + \
                       bytes.fromhex(tree)
        else:
            with open(file_path, 'rb') as single_file:
                file_object = write_object(git_dir, 'blob', single_file.read())
            contents = b'100644 ' + part.encode() + b'\x00' + \
                       bytes.fromhex(file_object)

        tree = write_object(git_dir, 'tree', contents)

    return tree


def write_commit(git_dir, git_tree):
    contents = b'tree ' + git_tree.encode() + \
               b'\nauthor . <.> 0 +0000\ncommitter . <.> 0 +0000\n\n'

    return write_object(git_dir, 'commit', contents)


def find_west_yml(project_dir):
    """Shallowest west.yml in the tree (fewest path separators).

    The root manifest must win over nested sample manifests (e.g. zephyr
    ships several under samples/); for zmk the only one is app/west.yml.
    """
    candidates = [
        os.path.join(dirpath, 'west.yml')
        for (dirpath, _, filenames) in os.walk(project_dir)
        if 'west.yml' in filenames
    ]
    if not candidates:
        return None
    return min(candidates, key=lambda path: path.count(os.path.sep))


if __name__ == '__main__':
    project_dir, head_sha = sys.argv[1], sys.argv[2]
    git_dir = os.path.join(project_dir, '.git')

    west_yml = find_west_yml(project_dir)

    init_repo(git_dir)

    if west_yml is not None:
        west_tree = write_single_file_tree(git_dir, west_yml, project_dir)
        manifest_rev = write_commit(git_dir, west_tree)
    else:
        manifest_rev = head_sha

    with open(os.path.join(git_dir, 'refs/heads/manifest-rev'), 'w') as ref:
        ref.write(manifest_rev + '\n')

    with open(os.path.join(git_dir, 'HEAD'), 'w') as head:
        head.write(head_sha + '\n')
