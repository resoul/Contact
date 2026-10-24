#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ObjCPlugin : NSObject

+ (NSString *)message NS_SWIFT_NAME(message());
+ (NSInteger)subtract:(NSInteger)lhs from:(NSInteger)rhs NS_SWIFT_NAME(subtract(_:from:));

@end

NS_ASSUME_NONNULL_END
