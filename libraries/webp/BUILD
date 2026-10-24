load("@rules_cc//cc:cc_library.bzl", "cc_library")

package(default_visibility = ["//visibility:private"])

_NON_ARM_SIMD_SUFFIXES = [
    "_avx2.c",
    "_mips32.c",
    "_mips_dsp_r2.c",
    "_msa.c",
    "_sse2.c",
    "_sse41.c",
    "_vsx.c",
]

_COMMON_DEFINES = ["WEBP_USE_THREAD=1"]

cc_library(
    name = "internal_headers",
    hdrs = glob([
        "libwebp/src/**/*.h",
        "libwebp/sharpyuv/*.h",
    ]),
    textual_hdrs = ["libwebp/src/dsp/cpu.c"],
    includes = ["libwebp", "libwebp/src"],
)

cc_library(
    name = "sharpyuv",
    srcs = glob(
        ["libwebp/sharpyuv/*.c"],
        exclude = ["libwebp/sharpyuv/*" + suffix for suffix in _NON_ARM_SIMD_SUFFIXES],
    ),
    hdrs = [
        "libwebp/sharpyuv/sharpyuv.h",
        "libwebp/sharpyuv/sharpyuv_csp.h",
    ],
    local_defines = _COMMON_DEFINES,
    linkstatic = True,
    target_compatible_with = ["@platforms//cpu:aarch64"],
    deps = [":internal_headers"],
)

cc_library(
    name = "webp",
    srcs = glob(
        [
            "libwebp/src/dec/*.c",
            "libwebp/src/enc/*.c",
            "libwebp/src/dsp/*.c",
            "libwebp/src/utils/*.c",
        ],
        exclude = ["libwebp/src/dsp/*" + suffix for suffix in _NON_ARM_SIMD_SUFFIXES],
    ),
    hdrs = [
        "libwebp/src/webp/decode.h",
        "libwebp/src/webp/encode.h",
        "libwebp/src/webp/types.h",
    ],
    includes = ["libwebp/src"],
    local_defines = _COMMON_DEFINES,
    linkopts = ["-lm"],
    linkstatic = True,
    target_compatible_with = ["@platforms//cpu:aarch64"],
    visibility = ["//visibility:public"],
    deps = [
        ":internal_headers",
        ":sharpyuv",
    ],
)

