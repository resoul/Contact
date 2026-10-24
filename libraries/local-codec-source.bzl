"""Expose an upstream CMake tree without loading its unrelated Bazel packages."""

def _source_impl(ctx):
    source = ctx.path(ctx.attr.marker).dirname.get_child(ctx.attr.source_dir)
    ctx.watch_tree(source)
    result = ctx.execute([
        "/usr/bin/python3", "-c",
        """import os, pathlib, sys
source, destination = map(pathlib.Path, sys.argv[1:])
for root, dirs, files in os.walk(source):
    dirs[:] = sorted(d for d in dirs if d != '.git')
    target = destination / pathlib.Path(root).relative_to(source)
    target.mkdir(parents=True, exist_ok=True)
    for name in sorted(files):
        if name not in ('.git', 'BUILD', 'BUILD.bazel'):
            (target / name).symlink_to(pathlib.Path(root) / name)
""", str(source), str(ctx.path("source")),
    ])
    if result.return_code:
        fail(result.stderr)
    ctx.file("BUILD.bazel", 'exports_files(["source/CMakeLists.txt"])\nfilegroup(name="sources", srcs=glob(["source/**"]), visibility=["//visibility:public"])\n')

local_codec_source = repository_rule(
    implementation = _source_impl,
    attrs = {"marker": attr.label(mandatory = True), "source_dir": attr.string(mandatory = True)},
    local = True,
)
