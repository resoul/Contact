load("@rules_cc//cc:objc_library.bzl", "objc_library")
load("@rules_swift//swift:swift_interop_hint.bzl", "swift_interop_hint")

exports_files(["SQLCipher-LICENSE.txt"])

swift_interop_hint(
    name = "swift_interop",
    module_name = "SQLCipher",
    module_map = "include/module.modulemap",
)

objc_library(
    name = "sqlcipher",
    srcs = ["Sources/sqlite3.c"],
    hdrs = glob(["include/*.h"]),
    includes = ["include"],
    enable_modules = True,
    module_name = "SQLCipher",
    aspect_hints = [":swift_interop"],
    # Keep the engine configuration compatible with GRDB.
    # GRDB needs decltype/progress/deprecated APIs omitted by Telegram's build.
    copts = [
        "-DSQLITE_HAS_CODEC=1",
        "-DSQLCIPHER_CRYPTO_CC=1",
        "-DSQLITE_EXTRA_INIT=sqlcipher_extra_init",
        "-DSQLITE_EXTRA_SHUTDOWN=sqlcipher_extra_shutdown",
        "-DSQLITE_THREADSAFE=1",
        "-DSQLITE_TEMP_STORE=2",
        "-DSQLITE_ENABLE_FTS5=1",
        "-DHAVE_USLEEP=1",
        "-DSQLITE_DEFAULT_MEMSTATUS=0",
        "-DSQLITE_MAX_MMAP_SIZE=0",
        "-DNDEBUG=1",
        "-Wno-ambiguous-macro",
    ],
    sdk_frameworks = ["Foundation", "Security"],
    visibility = ["//visibility:public"],
)
