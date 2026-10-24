#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSErrorDomain const MozjpegErrorDomain;
typedef NS_ERROR_ENUM(MozjpegErrorDomain, MozjpegErrorCode) {
    MozjpegErrorInvalidInput = 1,
    MozjpegErrorAllocationFailed,
    MozjpegErrorEncodingFailed,
    MozjpegErrorDecodingFailed,
};

// All calls are synchronous. Inputs are limited to 32 million pixels.
@interface MozJPEG : NSObject
+ (nullable NSData *)encode:(UIImage *)image quality:(NSInteger)quality
               progressive:(BOOL)progressive fast:(BOOL)fast error:(NSError **)error;
+ (nullable UIImage *)decode:(NSData *)data error:(NSError **)error;
// Quality 100 selects mathematically lossless JPEG XL after sRGB normalization.
+ (nullable NSData *)encodeXL:(UIImage *)image quality:(NSInteger)quality error:(NSError **)error;
+ (nullable UIImage *)decodeXL:(NSData *)data error:(NSError **)error;
@end

#ifdef __cplusplus
extern "C" {
#endif
// Telegram-compatible entry points: JPEG quality 72, progressive, fastest profile.
// The temporary path is retained for source compatibility; encoding stays in memory.
NSData * _Nullable compressJPEGData(UIImage *image, NSString *tempFilePath);
// Byte offsets of SOS markers after the first scan. Invalid JPEG returns [].
NSArray<NSNumber *> *extractJPEGDataScans(NSData *data);
// Telegram stripped-thumbnail v1: version, height, width, entropy payload.
NSData * _Nullable compressMiniThumbnail(UIImage *image, CGSize size);
NSData * _Nullable decodeTinyThumbnail(NSData *data);
UIImage * _Nullable decompressImage(NSData *sourceData);
NSData * _Nullable compressJPEGXLData(UIImage *sourceImage, int quality);
UIImage * _Nullable decompressJPEGXLData(NSData *data);
#ifdef __cplusplus
}
#endif
NS_ASSUME_NONNULL_END
