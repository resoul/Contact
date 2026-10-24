#import "ObjCXXPlugin.h"

#include "CPPPlugin.hpp"

@implementation ObjCXXPlugin

+ (NSString *)cppMessage {
    const std::string message = hello_bazel::cpp_plugin_message();
    return [NSString stringWithUTF8String:message.c_str()];
}

+ (NSString *)message {
    const std::string message = "Objective-C++ -> " + hello_bazel::cpp_plugin_message();
    return [NSString stringWithUTF8String:message.c_str()];
}

+ (NSInteger)multiply:(NSInteger)lhs by:(NSInteger)rhs {
    return hello_bazel::cpp_plugin_multiply(lhs, rhs);
}

@end
