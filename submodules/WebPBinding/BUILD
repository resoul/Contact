load("@rules_cc//cc:objc_library.bzl", "objc_library")
load("@rules_swift//swift:swift_interop_hint.bzl", "swift_interop_hint")

swift_interop_hint(
    name = "swift_interop",
    module_name = "WebPBinding",
)

objc_library(
    name = "WebPBinding",
    srcs = glob(["Sources/*.m"]),
    hdrs = glob(["PublicHeaders/WebPBinding/*.h"]),
    aspect_hints = [":swift_interop"],
    enable_modules = True,
    includes = ["PublicHeaders"],
    module_name = "WebPBinding",
    sdk_frameworks = ["Foundation", "UIKit", "CoreGraphics"],
    visibility = ["//visibility:public"],
    deps = ["//libraries/webp:webp"],
)

