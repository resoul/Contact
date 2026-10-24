load("//libraries:cmake-codecs.bzl", "apple_cmake_codec")
apple_cmake_codec(
    name = "libjxl",
    version = "0.12.0",
    headers = ["jxl/" + h for h in [
        "cms.h", "jxl_cms_export.h", "codestream_header.h", "cms_interface.h", "color_encoding.h", "decode.h", "encode.h",
        "jxl_export.h", "memory_manager.h", "parallel_runner.h", "stats.h", "types.h", "version.h",
    ]],
    archives = ["jxl", "jxl_cms", "hwy", "brotlicommon", "brotlidec", "brotlienc"],
)
