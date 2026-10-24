#import <Foundation/Foundation.h>

#import <FFMpegBinding/FFMpegAVSampleFormat.h>

NS_ASSUME_NONNULL_BEGIN

@class FFMpegAVFrame;

@interface FFMpegSWResample : NSObject

- (nullable instancetype)initWithSourceChannelCount:(NSInteger)sourceChannelCount sourceSampleRate:(NSInteger)sourceSampleRate sourceSampleFormat:(enum FFMpegAVSampleFormat)sourceSampleFormat destinationChannelCount:(NSInteger)destinationChannelCount destinationSampleRate:(NSInteger)destinationSampleRate destinationSampleFormat:(enum FFMpegAVSampleFormat)destinationSampleFormat;
- (NSData * _Nullable)resample:(FFMpegAVFrame *)frame;
/// Flush delayed samples after the decoder has reached EOF. Output is packed.
- (NSData * _Nullable)drain;

@end

NS_ASSUME_NONNULL_END
