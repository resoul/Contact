load("@rules_swift//swift:swift_library.bzl", "swift_library")
swift_library(
    name = "ContactStorage",
    module_name = "ContactStorage",
    srcs = glob(["Sources/**/*.swift"]),
    copts = ["-swift-version", "6"],
    deps = ["//libraries/grdb"],
    visibility = ["//visibility:public"],
)
