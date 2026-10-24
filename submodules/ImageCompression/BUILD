load("@rules_swift//swift:swift_library.bzl", "swift_library")
swift_library(
    name = "ImageCompression",
    module_name = "ImageCompression",
    srcs = glob(["Sources/*.swift"]),
    deps = ["//submodules/MozjpegBinding"],
    visibility = ["//visibility:public"],
)
