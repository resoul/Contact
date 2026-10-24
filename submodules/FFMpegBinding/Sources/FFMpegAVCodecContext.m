#import <FFMpegBinding/FFMpegAVCodecContext.h>

#import <FFMpegBinding/FFMpegAVFrame.h>
#import <FFMpegBinding/FFMpegAVCodec.h>

#import "libavformat/avformat.h"
#import "libavcodec/avcodec.h"

static enum AVPixelFormat getPreferredPixelFormat(__unused AVCodecContext *ctx, const enum AVPixelFormat *pix_fmts) {
    for (const enum AVPixelFormat *format = pix_fmts; *format != AV_PIX_FMT_NONE; ++format) {
        if (*format == AV_PIX_FMT_VIDEOTOOLBOX) return *format;
    }
    return pix_fmts[0];
}

@interface FFMpegAVCodecContext () {
    FFMpegAVCodec *_codec;
    AVCodecContext *_impl;
}

@end

@implementation FFMpegAVCodecContext

- (instancetype)initWithCodec:(FFMpegAVCodec *)codec {
    self = [super init];
    if (self != nil) {
        _codec = codec;
        _impl = avcodec_alloc_context3((AVCodec *)[codec impl]);
        if (!_impl) return nil;
        _impl->max_pixels = 4 * 1024 * 4 * 1024;
    }
    return self;
}

- (void)dealloc {
    if (_impl) {
        avcodec_free_context(&_impl);
    }
}

- (void *)impl {
    return _impl;
}

- (int32_t)channels {
    #if LIBAVFORMAT_VERSION_MAJOR >= 59
    return (int32_t)_impl->ch_layout.nb_channels;
    #else
    return (int32_t)_impl->channels;
    #endif
}

- (int32_t)sampleRate {
    return (int32_t)_impl->sample_rate;
}

- (FFMpegAVSampleFormat)sampleFormat {
    return (FFMpegAVSampleFormat)_impl->sample_fmt;
}

- (bool)open {
    int result = avcodec_open2(_impl, (AVCodec *)[_codec impl], nil);
    return result >= 0;
}

- (bool)sendEnd {
    int status = avcodec_send_packet(_impl, nil);
    return status == 0;
}

- (void)setupHardwareAccelerationIfPossible {
    if (av_hwdevice_ctx_create(&_impl->hw_device_ctx, AV_HWDEVICE_TYPE_VIDEOTOOLBOX, nil, nil, 0) >= 0) {
        _impl->get_format = getPreferredPixelFormat;
    }
}

- (void)setSkipLoopFilterToAll {
    _impl->skip_loop_filter = AVDISCARD_ALL;
}

- (FFMpegAVCodecContextReceiveResult)receiveIntoFrame:(FFMpegAVFrame *)frame {
    int status = avcodec_receive_frame(_impl, (AVFrame *)[frame impl]);
    if (status == 0) {
        return FFMpegAVCodecContextReceiveResultSuccess;
    } else if (status == AVERROR(EAGAIN)) {
        return FFMpegAVCodecContextReceiveResultNotEnoughData;
    } else if (status == AVERROR_EOF) {
        return FFMpegAVCodecContextReceiveResultEndOfStream;
    } else {
        return FFMpegAVCodecContextReceiveResultError;
    }
}

- (void)flushBuffers {
    avcodec_flush_buffers(_impl);
}

@end
