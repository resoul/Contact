#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface FFMpegGlobals : NSObject

+ (void)initializeGlobals;
+ (NSString *)version;

@end

NS_ASSUME_NONNULL_END
