genrule(
    name = "pkgconf",
    srcs = ["@codec_pkgconf//:sources", "@codec_pkgconf//:configure"],
    tools = ["build-pkgconf.sh"],
    outs = ["bin/pkgconf"],
    cmd = "bash $(location build-pkgconf.sh) $(location @codec_pkgconf//:configure) $@",
    executable = True,
    tags = ["requires-darwin"],
    visibility = ["//visibility:public"],
)
