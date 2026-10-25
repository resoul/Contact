load("@rules_cc//cc:objc_library.bzl", "objc_library")
load("@rules_swift//swift:swift_interop_hint.bzl", "swift_interop_hint")

exports_files(["LICENSE"])

core_headers = glob(["Source/**/*.h"])

# Match Texture/Core's public header selection; other headers stay private.
public_headers = glob([
    "Source/*.h",
    "Source/Details/**/*.h",
    "Source/Layout/**/*.h",
    "Source/Base/*.h",
    "Source/Debug/**/*.h",
    "Source/Private/ASCollectionView+Undeprecated.h",
    "Source/TextKit/ASTextNodeTypes.h",
    "Source/TextKit/ASTextKitComponents.h",
    "Source/TextExperiment/Component/*.h",
    "Source/TextExperiment/String/ASTextAttribute.h",
])

# CocoaPods normally provides these flat header paths through header maps.
genrule(
    name = "headers",
    srcs = core_headers,
    outs = ["include/AsyncDisplayKit/" + h.split("/")[-1] for h in core_headers],
    cmd = "\n".join([
        "printf '#import \"libraries/AsyncDisplayKit/" + h + "\"\n' > $(location include/AsyncDisplayKit/" + h.split("/")[-1] + ")"
        for h in core_headers
    ]),
)

swift_interop_hint(
    name = "swift_interop",
    module_name = "AsyncDisplayKit",
)

objc_library(
    name = "AsyncDisplayKit",
    srcs = glob(["Source/**/*.mm"]) + core_headers + [
        "include/AsyncDisplayKit/" + h.split("/")[-1]
        for h in core_headers
        if h not in public_headers
    ],
    hdrs = ["include/AsyncDisplayKit/" + h.split("/")[-1] for h in public_headers],
    includes = ["include"],
    enable_modules = True,
    module_name = "AsyncDisplayKit",
    aspect_hints = [":swift_interop"],
    copts = ["-fno-exceptions"],
    cxxopts = ["-std=c++11"],
    defines = [
        "AS_USE_VIDEO=0",
        "AS_USE_MAPKIT=0",
        "AS_USE_PHOTOS=0",
        "AS_USE_ASSETS_LIBRARY=0",
        "YOGA=0",
    ],
    sdk_frameworks = [
        "Foundation",
        "UIKit",
        "QuartzCore",
        "CoreGraphics",
        "CoreText",
    ],
    sdk_dylibs = ["c++"],
    visibility = ["//visibility:public"],
)
