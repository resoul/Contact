#ifndef HELLO_BAZEL_C_PLUGIN_H
#define HELLO_BAZEL_C_PLUGIN_H

#ifdef __cplusplus
extern "C" {
#endif

const char *c_plugin_message(void);
int c_plugin_add(int lhs, int rhs);

#ifdef __cplusplus
}
#endif

#endif
