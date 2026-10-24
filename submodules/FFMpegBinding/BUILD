load("@rules_cc//cc:objc_library.bzl", "objc_library")
load("@rules_swift//swift:swift_interop_hint.bzl", "swift_interop_hint")

swift_interop_hint(
    name = "swift_interop",
    module_name = "FFMpegBinding",
)

objc_library(
    name = "FFMpegBinding",
    srcs = glob(["Sources/*.m", "Sources/*.h"]),
    hdrs = glob(["Public/FFMpegBinding/*.h"]),
    aspect_hints = [":swift_interop"],
    enable_modules = True,
    includes = ["Public"],
    module_name = "FFMpegBinding",
    sdk_frameworks = ["Foundation", "CoreMedia", "CoreVideo", "CoreImage", "UIKit"],
    visibility = ["//visibility:public"],
    deps = ["//libraries/ffmpeg"],
)
