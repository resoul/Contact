#import "FFMpegRemux.h"
#include <libavformat/avformat.h>
#include <math.h>

BOOL FFMpegRemuxFile(NSString *source, NSString *destination, BOOL transportStream, double offset) {
    if (!isfinite(offset) || fabs(offset) > 86400 * 365 || [source.stringByStandardizingPath isEqual:destination.stringByStandardizingPath]) return NO;
    AVFormatContext *input = NULL, *output = NULL;
    AVPacket *packet = NULL;
    int *mapping = NULL;
    int result = avformat_open_input(&input, source.UTF8String, NULL, NULL);
    if (result < 0) goto done;
    if ((result = avformat_find_stream_info(input, NULL)) < 0) goto done;
    if ((result = avformat_alloc_output_context2(&output, NULL, transportStream ? "mpegts" : "mp4", destination.UTF8String)) < 0) goto done;
    mapping = av_malloc_array(input->nb_streams, sizeof(*mapping));
    if (!mapping) { result = AVERROR(ENOMEM); goto done; }
    for (unsigned i = 0; i < input->nb_streams; ++i) {
        AVStream *in = input->streams[i];
        mapping[i] = -1;
        if (in->codecpar->codec_type != AVMEDIA_TYPE_VIDEO && in->codecpar->codec_type != AVMEDIA_TYPE_AUDIO) continue;
        if (transportStream && in->codecpar->codec_type == AVMEDIA_TYPE_AUDIO && in->codecpar->codec_id != AV_CODEC_ID_AAC) continue;
        AVStream *out = avformat_new_stream(output, NULL);
        if (!out) { result = AVERROR(ENOMEM); goto done; }
        mapping[i] = out->index;
        if ((result = avcodec_parameters_copy(out->codecpar, in->codecpar)) < 0) goto done;
        out->codecpar->codec_tag = 0;
        out->time_base = in->time_base;
        av_dict_copy(&out->metadata, in->metadata, 0);
    }
    if (output->nb_streams == 0) { result = AVERROR_STREAM_NOT_FOUND; goto done; }
    av_dict_copy(&output->metadata, input->metadata, 0);
    if ((result = avio_open(&output->pb, destination.UTF8String, AVIO_FLAG_WRITE)) < 0) goto done;
    if ((result = avformat_write_header(output, NULL)) < 0) goto done;
    packet = av_packet_alloc();
    if (!packet) { result = AVERROR(ENOMEM); goto done; }
    while ((result = av_read_frame(input, packet)) >= 0) {
        int index = packet->stream_index;
        if (index < 0 || (unsigned)index >= input->nb_streams || mapping[index] < 0) {
            av_packet_unref(packet);
            continue;
        }
        AVStream *out = output->streams[mapping[index]];
        av_packet_rescale_ts(packet, input->streams[index]->time_base, out->time_base);
        int64_t shift = av_rescale_q((int64_t)(offset * AV_TIME_BASE), AV_TIME_BASE_Q, out->time_base);
        if (packet->pts != AV_NOPTS_VALUE) packet->pts += shift;
        if (packet->dts != AV_NOPTS_VALUE) packet->dts += shift;
        packet->stream_index = out->index;
        packet->pos = -1;
        result = av_interleaved_write_frame(output, packet);
        av_packet_unref(packet);
        if (result < 0) goto done;
    }
    if (result == AVERROR_EOF) result = av_write_trailer(output);
done:
    av_packet_free(&packet);
    av_free(mapping);
    avformat_close_input(&input);
    if (output) {
        int closed = output->pb ? avio_closep(&output->pb) : 0;
        if (result >= 0 && closed < 0) result = closed;
        avformat_free_context(output);
    }
    return result >= 0;
}
