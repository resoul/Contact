"""Pinned upstream CMake builds for the JPEG and JPEG XL codecs."""
load("@rules_cc//cc:cc_import.bzl", "cc_import")
load("@rules_cc//cc:cc_library.bzl", "cc_library")

def apple_cmake_codec(name, version, headers, archives):
    public_headers = ["include/" + header for header in headers]
    libraries = ["lib/lib" + archive + ".a" for archive in archives]
    outputs = public_headers + libraries + ["build-info.txt", "lib/pkgconfig/" + name + ".pc"]
    for setting, constraints in [
        ("device", ["@platforms//os:ios", "@apple_support//constraints:device"]),
        ("simulator", ["@platforms//os:ios", "@apple_support//constraints:simulator"]),
        ("macos", ["@platforms//os:macos"]),
    ]:
        native.config_setting(name = setting, constraint_values = constraints)
    sources = ["@codec_libjxl_sources//:sources", "@codec_libjxl_sources//:source/CMakeLists.txt"] if name == "libjxl" else native.glob([name + "/**"], exclude = [name + "/**/.git", name + "/**/.git/**"])
    source_path = "$(location @codec_libjxl_sources//:source/CMakeLists.txt)" if name == "libjxl" else native.package_name() + "/" + name
    native.genrule(
        name = name + "_build",
        srcs = sources + ["@codec_cmake//:runtime"],
        tools = ["//libraries:build-cmake-codec.sh", "@codec_cmake//:CMake.app/Contents/bin/cmake", "@codec_ninja//:ninja"],
        outs = outputs,
        cmd = select({
            ":" + setting: "bash $(location //libraries:build-cmake-codec.sh) %s %s $(COMPILATION_MODE) %s %s $(RULEDIR) $(location @codec_cmake//:CMake.app/Contents/bin/cmake) $(location @codec_ninja//:ninja)" % (name, cpu, source_path, version)
            for setting, cpu in [("device", "ios_arm64"), ("simulator", "ios_sim_arm64"), ("macos", "darwin_arm64")]
        }),
        target_compatible_with = ["@platforms//cpu:aarch64"],
        tags = ["requires-darwin"],
    )
    for archive in archives:
        cc_import(name = archive + "_archive", static_library = "lib/lib" + archive + ".a")
    cc_library(
        name = name,
        hdrs = public_headers,
        includes = ["include"],
        deps = [":" + archive + "_archive" for archive in archives],
        linkopts = ["-lm"] + (["-lc++"] if name == "libjxl" else []),
        visibility = ["//visibility:public"],
        target_compatible_with = ["@platforms//cpu:aarch64"],
    )
    native.filegroup(name = "distribution", srcs = outputs, visibility = ["//visibility:public"])
