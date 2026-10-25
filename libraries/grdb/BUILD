load("@rules_apple//apple:resources.bzl", "apple_resource_bundle")
load("@rules_swift//swift:swift_library.bzl", "swift_library")

apple_resource_bundle(
    name = "GRDBResources",
    bundle_name = "GRDB",
    resources = [
        "@grdb_sources//:GRDB/PrivacyInfo.xcprivacy",
        "@grdb_sources//:LICENSE",
        "//libraries/sqlcipher:SQLCipher-LICENSE.txt",
    ],
)

swift_library(
    name = "grdb",
    srcs = ["@grdb_sources//:swift_sources"],
    module_name = "GRDB",
    defines = ["GRDBCIPHER", "SQLITE_HAS_CODEC", "SQLITE_ENABLE_FTS5"],
    copts = ["-swift-version", "6", "-enable-upcoming-feature", "MemberImportVisibility"],
    data = [":GRDBResources"],
    deps = ["//libraries/sqlcipher"],
    visibility = ["//visibility:public"],
)
