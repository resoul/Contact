#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Keep C++ types out of the public interface so Swift can import this module.
@interface ObjCXXPlugin : NSObject

+ (NSString *)message NS_SWIFT_NAME(message());
+ (NSString *)cppMessage NS_SWIFT_NAME(cppMessage());
+ (NSInteger)multiply:(NSInteger)lhs by:(NSInteger)rhs NS_SWIFT_NAME(multiply(_:by:));

@end

NS_ASSUME_NONNULL_END
