#include "CPPPlugin.hpp"

namespace hello_bazel {

std::string cpp_plugin_message() {
    return std::string("C++ plugin OK");
}

std::int64_t cpp_plugin_multiply(std::int64_t lhs, std::int64_t rhs) {
    return lhs * rhs;
}

}  // namespace hello_bazel
