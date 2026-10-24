#include <libavcodec/avcodec.h>
#import <FFMpegBinding/FFMpegVideoWriter.h>
#import <FFMpegBinding/FFMpegAVFrame.h>
#include <libavformat/avformat.h>
#include <libavutil/opt.h>

@implementation FFMpegVideoWriter {
    AVFormatContext *_format;
    AVCodecContext *_codec;
    AVStream *_stream;
    int64_t _pts;
}

- (void)close {
    avcodec_free_context(&_codec);
    if (_format) {
        if (_format->pb) avio_closep(&_format->pb);
        avformat_free_context(_format);
        _format = NULL;
    }
    _stream = NULL;
}

- (void)dealloc { [self close]; }

- (bool)setupWithOutputPath:(NSString *)outputPath width:(int)width height:(int)height bitrate:(int64_t)bitrate framerate:(int32_t)framerate {
    [self close];
    if (width <= 0 || height <= 0 || width > 8192 || height > 8192 || bitrate <= 0 || framerate <= 0) return false;
    if (avformat_alloc_output_context2(&_format, NULL, "matroska", outputPath.UTF8String) < 0) return false;
    const AVCodec *encoder = avcodec_find_encoder_by_name("libvpx-vp9");
    if (!encoder || !(_codec = avcodec_alloc_context3(encoder))) { [self close]; return false; }
    _codec->width = width;
    _codec->height = height;
    _codec->pix_fmt = AV_PIX_FMT_YUVA420P;
    _codec->time_base = (AVRational){1, framerate};
    _codec->framerate = (AVRational){framerate, 1};
    _codec->bit_rate = bitrate;
    _codec->color_range = AVCOL_RANGE_MPEG;
    _codec->color_primaries = AVCOL_PRI_BT709;
    _codec->colorspace = AVCOL_SPC_BT709;
    if (_format->oformat->flags & AVFMT_GLOBALHEADER) _codec->flags |= AV_CODEC_FLAG_GLOBAL_HEADER;
    av_opt_set(_codec->priv_data, "deadline", "realtime", 0);
    av_opt_set(_codec->priv_data, "cpu-used", "8", 0);
    av_opt_set(_codec->priv_data, "lag-in-frames", "0", 0);
    av_opt_set(_codec->priv_data, "auto-alt-ref", "0", 0);
    if (avcodec_open2(_codec, encoder, NULL) < 0 || !(_stream = avformat_new_stream(_format, NULL)) ||
        avcodec_parameters_from_context(_stream->codecpar, _codec) < 0) { [self close]; return false; }
    _stream->time_base = _codec->time_base;
    _stream->avg_frame_rate = _codec->framerate;
    av_dict_set(&_stream->metadata, "alpha_mode", "1", 0);
    if (avio_open(&_format->pb, outputPath.UTF8String, AVIO_FLAG_WRITE) < 0 || avformat_write_header(_format, NULL) < 0) { [self close]; return false; }
    _pts = 0;
    return true;
}

- (BOOL)writeAvailablePackets {
    AVPacket *packet = av_packet_alloc();
    if (!packet) return NO;
    int result;
    while ((result = avcodec_receive_packet(_codec, packet)) >= 0) {
        if (packet->duration <= 0) packet->duration = 1;
        av_packet_rescale_ts(packet, _codec->time_base, _stream->time_base);
        packet->stream_index = _stream->index;
        result = av_interleaved_write_frame(_format, packet);
        av_packet_unref(packet);
        if (result < 0) break;
    }
    av_packet_free(&packet);
    return result == AVERROR(EAGAIN) || result == AVERROR_EOF;
}

- (bool)encodeFrame:(FFMpegAVFrame *)frame {
    if (!_codec || !_stream) return false;
    AVFrame *value = [frame impl];
    if (value->width != _codec->width || value->height != _codec->height || value->format != _codec->pix_fmt) return false;
    value->pts = _pts++;
    value->duration = 1;
    value->color_range = _codec->color_range;
    value->color_primaries = _codec->color_primaries;
    value->colorspace = _codec->colorspace;
    return avcodec_send_frame(_codec, value) >= 0 && [self writeAvailablePackets];
}

- (bool)finalizeVideo {
    if (!_codec || !_format) return false;
    BOOL success = avcodec_send_frame(_codec, NULL) >= 0 && [self writeAvailablePackets];
    if (av_write_trailer(_format) < 0) success = NO;
    [self close];
    return success;
}
@end
