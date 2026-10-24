#include "CPlugin.h"

const char *c_plugin_message(void) {
    return "C plugin OK";
}

int c_plugin_add(int lhs, int rhs) {
    return lhs + rhs;
}
