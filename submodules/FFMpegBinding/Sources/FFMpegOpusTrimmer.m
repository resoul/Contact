#import <FFMpegBinding/FFMpegOpusTrimmer.h>
#include <libavformat/avformat.h>
#include <math.h>

@implementation FFMpegOpusTrimmer
+ (bool)trim:(NSString *)path to:(NSString *)outputPath start:(double)start end:(double)end {
    if (!isfinite(start) || !isfinite(end) || start < 0 || end <= start || [path.stringByStandardizingPath isEqual:outputPath.stringByStandardizingPath]) return false;
    AVFormatContext *input = NULL, *output = NULL;
    AVPacket *packet = NULL;
    AVStream *in = NULL, *out = NULL;
    int audio = -1, result = avformat_open_input(&input, path.UTF8String, NULL, NULL);
    int64_t first = AV_NOPTS_VALUE;
    if (result < 0 || (result = avformat_find_stream_info(input, NULL)) < 0) goto done;
    for (unsigned i = 0; i < input->nb_streams; ++i) {
        if (input->streams[i]->codecpar->codec_id == AV_CODEC_ID_OPUS) { audio = (int)i; break; }
    }
    if (audio < 0) { result = AVERROR_STREAM_NOT_FOUND; goto done; }
    in = input->streams[audio];
    if ((result = avformat_alloc_output_context2(&output, NULL, "ogg", outputPath.UTF8String)) < 0) goto done;
    out = avformat_new_stream(output, NULL);
    if (!out) { result = AVERROR(ENOMEM); goto done; }
    if ((result = avcodec_parameters_copy(out->codecpar, in->codecpar)) < 0) goto done;
    out->time_base = in->time_base;
    if ((result = avio_open(&output->pb, outputPath.UTF8String, AVIO_FLAG_WRITE)) < 0 ||
        (result = avformat_write_header(output, NULL)) < 0) goto done;
    packet = av_packet_alloc();
    if (!packet) { result = AVERROR(ENOMEM); goto done; }
    while ((result = av_read_frame(input, packet)) >= 0) {
        int64_t pts = packet->pts != AV_NOPTS_VALUE ? packet->pts : packet->dts;
        double seconds = pts == AV_NOPTS_VALUE ? -1 : pts * av_q2d(in->time_base);
        if (packet->stream_index != audio || seconds < start) { av_packet_unref(packet); continue; }
        if (seconds >= end) { result = AVERROR_EOF; break; }
        if (first == AV_NOPTS_VALUE) first = pts;
        if (packet->pts != AV_NOPTS_VALUE) packet->pts -= first;
        if (packet->dts != AV_NOPTS_VALUE) packet->dts -= first;
        av_packet_rescale_ts(packet, in->time_base, out->time_base);
        packet->stream_index = 0;
        packet->pos = -1;
        result = av_interleaved_write_frame(output, packet);
        av_packet_unref(packet);
        if (result < 0) break;
    }
    if (result == AVERROR_EOF) result = first == AV_NOPTS_VALUE ? AVERROR_INVALIDDATA : av_write_trailer(output);
done:
    av_packet_free(&packet);
    avformat_close_input(&input);
    if (output) {
        int closed = output->pb ? avio_closep(&output->pb) : 0;
        if (result >= 0 && closed < 0) result = closed;
        avformat_free_context(output);
    }
    return result >= 0;
}
@end
