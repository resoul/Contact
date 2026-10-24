#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const WebPErrorDomain;

typedef NS_ERROR_ENUM(WebPErrorDomain, WebPErrorCode) {
    WebPErrorInvalidImage = 1,
    WebPErrorInvalidQuality,
    WebPErrorAllocationFailed,
    WebPErrorEncodingFailed,
};

@interface WebP : NSObject

+ (nullable UIImage *)convertFromWebP:(NSData *)data;

+ (nullable NSData *)convertToWebP:(UIImage *)image
                          quality:(CGFloat)quality
                            error:(NSError * _Nullable * _Nullable)error;

+ (nullable NSData *)convertToLosslessWebP:(UIImage *)image
                                   error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
