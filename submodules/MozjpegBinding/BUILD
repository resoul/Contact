load("@rules_cc//cc:objc_library.bzl", "objc_library")
load("@rules_swift//swift:swift_interop_hint.bzl", "swift_interop_hint")
swift_interop_hint(name = "swift_interop", module_name = "MozjpegBinding")
objc_library(
    name = "MozjpegBinding",
    srcs = glob(["Sources/*.mm"]),
    hdrs = glob(["PublicHeaders/MozjpegBinding/*.h"]),
    aspect_hints = [":swift_interop"],
    enable_modules = True,
    includes = ["PublicHeaders"],
    module_name = "MozjpegBinding",
    sdk_frameworks = ["Foundation", "UIKit", "CoreGraphics"],
    deps = ["//libraries/mozjpeg", "//libraries/libjxl"],
    visibility = ["//visibility:public"],
)
