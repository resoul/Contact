#import <FFMpegBinding/FFMpegSWResample.h>
#import <FFMpegBinding/FFMpegAVFrame.h>
#include <libavcodec/avcodec.h>
#include <libswresample/swresample.h>

@implementation FFMpegSWResample {
    int _sourceSampleRate;
    enum AVSampleFormat _sourceFormat;
    int _destinationChannels;
    int _destinationRate;
    enum AVSampleFormat _destinationFormat;
    AVChannelLayout _sourceLayout;
    SwrContext *_context;
}

- (instancetype)initWithSourceChannelCount:(NSInteger)sourceChannelCount sourceSampleRate:(NSInteger)sourceSampleRate sourceSampleFormat:(enum FFMpegAVSampleFormat)sourceSampleFormat destinationChannelCount:(NSInteger)destinationChannelCount destinationSampleRate:(NSInteger)destinationSampleRate destinationSampleFormat:(enum FFMpegAVSampleFormat)destinationSampleFormat {
    self = [super init];
    if (self) {
        if (sourceChannelCount <= 0 || sourceSampleRate <= 0 || destinationChannelCount <= 0 || destinationChannelCount > 32 || destinationSampleRate <= 0 || av_sample_fmt_is_planar((enum AVSampleFormat)destinationSampleFormat) || av_get_bytes_per_sample((enum AVSampleFormat)destinationSampleFormat) <= 0) return nil;
        _sourceSampleRate = (int)sourceSampleRate;
        _sourceFormat = (enum AVSampleFormat)sourceSampleFormat;
        _destinationChannels = (int)destinationChannelCount;
        _destinationRate = (int)destinationSampleRate;
        _destinationFormat = (enum AVSampleFormat)destinationSampleFormat;
    }
    return self;
}

- (void)dealloc {
    swr_free(&_context);
    av_channel_layout_uninit(&_sourceLayout);
}

- (BOOL)configureForFrame:(AVFrame *)frame {
    int rate = frame->sample_rate > 0 ? frame->sample_rate : _sourceSampleRate;
    if (rate <= 0 || !av_channel_layout_check(&frame->ch_layout)) return NO;
    if (_context && rate == _sourceSampleRate && frame->format == _sourceFormat && av_channel_layout_compare(&_sourceLayout, &frame->ch_layout) == 0) return YES;
    swr_free(&_context);
    av_channel_layout_uninit(&_sourceLayout);
    AVChannelLayout destination;
    av_channel_layout_default(&destination, _destinationChannels);
    int result = swr_alloc_set_opts2(&_context, &destination, _destinationFormat, _destinationRate,
        &frame->ch_layout, frame->format, rate, 0, NULL);
    av_channel_layout_uninit(&destination);
    if (result < 0 || swr_init(_context) < 0 || av_channel_layout_copy(&_sourceLayout, &frame->ch_layout) < 0) {
        swr_free(&_context);
        return NO;
    }
    _sourceSampleRate = rate;
    _sourceFormat = frame->format;
    return YES;
}

- (NSData *)convertFrame:(AVFrame *)frame {
    if (!_context) return nil;
    int capacity = swr_get_out_samples(_context, frame ? frame->nb_samples : 0);
    if (capacity == 0) return frame ? [NSData data] : nil;
    if (capacity < 0 || capacity > 8 * 1024 * 1024) return nil;
    int size = av_samples_get_buffer_size(NULL, _destinationChannels, capacity, _destinationFormat, 1);
    if (size <= 0) return nil;
    uint8_t *buffer = av_malloc(size);
    if (!buffer) return nil;
    int samples = swr_convert(_context, &buffer, capacity,
        frame ? (const uint8_t **)frame->extended_data : NULL, frame ? frame->nb_samples : 0);
    NSData *result = nil;
    if (samples == 0 && frame) result = [NSData data];
    if (samples > 0) {
        int bytes = av_samples_get_buffer_size(NULL, _destinationChannels, samples, _destinationFormat, 1);
        if (bytes > 0) result = [NSData dataWithBytes:buffer length:bytes];
    }
    av_free(buffer);
    return result;
}

- (NSData *)resample:(FFMpegAVFrame *)frame {
    AVFrame *impl = [frame impl];
    if (![self configureForFrame:impl]) return nil;
    return [self convertFrame:impl];
}

- (NSData *)drain { return [self convertFrame:NULL]; }
@end
