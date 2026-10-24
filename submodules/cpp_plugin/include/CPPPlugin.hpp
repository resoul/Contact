#ifndef HELLO_BAZEL_CPP_PLUGIN_HPP
#define HELLO_BAZEL_CPP_PLUGIN_HPP

#include <cstdint>
#include <string>

namespace hello_bazel {

std::string cpp_plugin_message();
std::int64_t cpp_plugin_multiply(std::int64_t lhs, std::int64_t rhs);

}  // namespace hello_bazel

#endif
