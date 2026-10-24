"""Build upstream codec projects and export static libraries to Bazel/FFmpeg."""

load("@rules_cc//cc:cc_import.bzl", "cc_import")
load("@rules_cc//cc:cc_library.bzl", "cc_library")

def apple_codec(name, source_dir, version, headers, header_dir = None):
    """Builds one pinned upstream codec for an Apple arm64 platform."""
    header_dir = header_dir or name
    public_headers = ["include/" + header_dir + "/" + header for header in headers]
    library = "lib/lib" + name + ".a"
    distribution = public_headers + [library, "lib/pkgconfig/" + name + ".pc"]
    sources = native.glob(
        [source_dir + "/**"],
        exclude = [source_dir + "/.git", source_dir + "/.git/**"],
    )
    tools = ["//libraries:build-codec.sh"]
    models = "-"
    if name == "vpx":
        meson = "-"
        ninja = "-"
    else:
        sources += ["@codec_meson//:runtime"]
        tools += ["@codec_meson//:meson.py", "@codec_ninja//:ninja"]
        meson = "$(location @codec_meson//:meson.py)"
        ninja = "$(location @codec_ninja//:ninja)"
        if name == "opus":
            sources += ["@codec_opus_models//file"]
            models = "$(location @codec_opus_models//file)"

    native.config_setting(
        name = "ios_device",
        constraint_values = ["@platforms//os:ios", "@apple_support//constraints:device"],
    )
    native.config_setting(
        name = "ios_simulator",
        constraint_values = ["@platforms//os:ios", "@apple_support//constraints:simulator"],
    )
    native.config_setting(
        name = "macos",
        constraint_values = ["@platforms//os:macos"],
    )
    commands = {}
    for setting, cpu in [("ios_device", "ios_arm64"), ("ios_simulator", "ios_sim_arm64"), ("macos", "darwin_arm64")]:
        commands[":" + setting] = "bash $(location //libraries:build-codec.sh) %s %s $(COMPILATION_MODE) %s %s $(RULEDIR) '%s' '%s' '%s'" % (
            name,
            cpu,
            native.package_name() + "/" + source_dir,
            version,
            meson,
            ninja,
            models,
        )

    native.genrule(
        name = name + "_build",
        srcs = sources,
        tools = tools,
        outs = distribution,
        cmd = select(commands),
        tags = ["requires-darwin"],
        target_compatible_with = ["@platforms//cpu:aarch64"],
    )

    native.filegroup(
        name = "distribution",
        srcs = distribution,
        visibility = ["//visibility:public"],
    )

    cc_import(
        name = "archive",
        static_library = library,
    )

    cc_library(
        name = name,
        hdrs = public_headers,
        includes = ["include"],
        linkopts = ["-lm"],
        target_compatible_with = ["@platforms//cpu:aarch64"],
        visibility = ["//visibility:public"],
        deps = [":archive"],
    )
