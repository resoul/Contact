#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const FFMpegMediaErrorDomain;

@interface FFMpegPreviewFrame : NSObject
@property (nonatomic, copy, readonly) NSData *pngData;
@property (nonatomic, readonly) double time;
@end

@interface FFMpegDecodedVideo : NSObject
@property (nonatomic, copy, readonly) NSArray<FFMpegPreviewFrame *> *frames;
/// Interleaved signed 16-bit little-endian PCM, 48 kHz, stereo.
@property (nonatomic, copy, readonly) NSData *pcmData;
@property (nonatomic, copy, readonly) NSString *videoCodec;
@property (nonatomic, copy, readonly) NSString *audioCodec;
@property (nonatomic, readonly) NSInteger width;
@property (nonatomic, readonly) NSInteger height;
@property (nonatomic, readonly) NSInteger videoFrameCount;
@property (nonatomic, readonly) NSInteger audioFrameCount;
@property (nonatomic, readonly) double sourceDuration;
@property (nonatomic, readonly) double previewDuration;
@property (nonatomic, readonly) double framesPerSecond;
@end

@interface FFMpegMedia : NSObject
/// Synchronous bounded preview for diagnostics. Run off the main thread.
/// Decodes up to 10 seconds; PNG previews have a maximum edge of 320 pixels
/// and at most 30 previews/second. Supports 8-bit YUV420/YUVA420 preview pixels.
+ (nullable FFMpegDecodedVideo *)decodeVideo:(NSString *)path
                              maxDuration:(double)maxDuration
                                    error:(NSError * _Nullable * _Nullable)error;
@end

NS_ASSUME_NONNULL_END
