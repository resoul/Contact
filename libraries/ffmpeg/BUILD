load("@rules_cc//cc:cc_import.bzl", "cc_import")
load("@rules_cc//cc:cc_library.bzl", "cc_library")
load(":headers.bzl", "FFMPEG_HEADERS")

package(default_visibility = ["//visibility:private"])

_LIBRARIES = ["avformat", "avcodec", "swresample", "avutil"]
_HEADERS = ["include/" + header for header in FFMPEG_HEADERS]
_OUTPUTS = _HEADERS + ["lib/lib" + lib + ".a" for lib in _LIBRARIES] + [
    "lib/pkgconfig/lib" + lib + ".pc"
    for lib in _LIBRARIES
] + ["build-info.txt"]

config_setting(
    name = "ios_device",
    constraint_values = ["@platforms//os:ios", "@apple_support//constraints:device"],
)

config_setting(
    name = "ios_simulator",
    constraint_values = ["@platforms//os:ios", "@apple_support//constraints:simulator"],
)

config_setting(
    name = "macos",
    constraint_values = ["@platforms//os:macos"],
)

_COMMAND = """bash $(location build-ffmpeg.sh) {cpu} $(COMPILATION_MODE) $(RULEDIR) \
    $(location //libraries/build-tools:pkgconf) \
    $(location @codec_gas_preprocessor//file) \
    $(locations //libraries/libvpx:distribution) \
    $(locations //libraries/opus:distribution) \
    $(locations //libraries/dav1d:distribution)
"""

genrule(
    name = "ffmpeg_build",
    srcs = glob(["ffmpeg/**"], exclude = ["ffmpeg/.git", "ffmpeg/.git/**"]) + [
        "//libraries/libvpx:distribution",
        "//libraries/opus:distribution",
        "//libraries/dav1d:distribution",
    ],
    tools = [
        "build-ffmpeg.sh",
        "//libraries/build-tools:pkgconf",
        "@codec_gas_preprocessor//file",
    ],
    outs = _OUTPUTS,
    cmd = select({
        ":ios_device": _COMMAND.format(cpu = "ios_arm64"),
        ":ios_simulator": _COMMAND.format(cpu = "ios_sim_arm64"),
        ":macos": _COMMAND.format(cpu = "darwin_arm64"),
    }),
    tags = ["requires-darwin"],
    target_compatible_with = ["@platforms//cpu:aarch64"],
)

filegroup(
    name = "distribution",
    srcs = _OUTPUTS,
    visibility = ["//visibility:public"],
)

[
    cc_import(
        name = lib + "_archive",
        static_library = "lib/lib" + lib + ".a",
    )
    for lib in _LIBRARIES
]

cc_library(
    name = "ffmpeg",
    hdrs = _HEADERS,
    includes = ["include"],
    linkopts = [
        "-lbz2",
        "-liconv",
        "-lz",
        "-framework AudioToolbox",
        "-framework CoreAudio",
        "-framework CoreFoundation",
        "-framework CoreMedia",
        "-framework CoreVideo",
        "-framework VideoToolbox",
    ],
    target_compatible_with = ["@platforms//cpu:aarch64"],
    visibility = ["//visibility:public"],
    deps = [":" + lib + "_archive" for lib in _LIBRARIES] + [
        "//libraries/libvpx:vpx",
        "//libraries/opus:opus",
        "//libraries/dav1d:dav1d",
    ],
)
