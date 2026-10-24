#import <FFMpegBinding/FFMpegBinding.h>
#import <UIKit/UIKit.h>
#import <CoreImage/CoreImage.h>
#include <libavcodec/avcodec.h>
#include <libavutil/pixdesc.h>
#include <math.h>

NSErrorDomain const FFMpegMediaErrorDomain = @"org.airlance.Contact.FFMpeg";

@interface FFMpegPreviewFrame ()
@property (nonatomic, copy) NSData *pngData;
@property (nonatomic) double time;
@end
@implementation FFMpegPreviewFrame
@end

@interface FFMpegDecodedVideo ()
@property (nonatomic, copy) NSArray<FFMpegPreviewFrame *> *frames;
@property (nonatomic, copy) NSData *pcmData;
@property (nonatomic, copy) NSString *videoCodec;
@property (nonatomic, copy) NSString *audioCodec;
@property (nonatomic) NSInteger width;
@property (nonatomic) NSInteger height;
@property (nonatomic) NSInteger videoFrameCount;
@property (nonatomic) NSInteger audioFrameCount;
@property (nonatomic) double sourceDuration;
@property (nonatomic) double previewDuration;
@property (nonatomic) double framesPerSecond;
@end
@implementation FFMpegDecodedVideo
@end

static void MediaError(NSError **error, NSInteger code, NSString *message) {
    if (error) *error = [NSError errorWithDomain:FFMpegMediaErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey: message}];
}

static NSData *PreviewPNG(FFMpegAVFrame *value, double rotation) {
    AVFrame *frame = [value impl];
    if (frame->format != AV_PIX_FMT_YUV420P && frame->format != AV_PIX_FMT_YUVJ420P && frame->format != AV_PIX_FMT_YUVA420P) return nil;
    int width = frame->width, height = frame->height;
    if (width <= 0 || height <= 0) return nil;
    BOOL fullRange = frame->color_range == AVCOL_RANGE_JPEG || frame->format == AV_PIX_FMT_YUVJ420P;
    CVPixelBufferRef buffer = NULL;
    if (CVPixelBufferCreate(NULL, width, height,
        fullRange ? kCVPixelFormatType_420YpCbCr8BiPlanarFullRange : kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
        (__bridge CFDictionaryRef)@{(id)kCVPixelBufferIOSurfacePropertiesKey: @{}}, &buffer) != kCVReturnSuccess) return nil;
    if (CVPixelBufferLockBaseAddress(buffer, 0) != kCVReturnSuccess) { CVPixelBufferRelease(buffer); return nil; }
    uint8_t *yPlane = CVPixelBufferGetBaseAddressOfPlane(buffer, 0);
    uint8_t *uvPlane = CVPixelBufferGetBaseAddressOfPlane(buffer, 1);
    size_t yStride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0);
    size_t uvStride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 1);
    for (int y = 0; y < height; ++y) memcpy(yPlane + y * yStride, frame->data[0] + (ptrdiff_t)y * frame->linesize[0], width);
    for (int y = 0; y < (height + 1) / 2; ++y) {
        const uint8_t *u = frame->data[1] + (ptrdiff_t)y * frame->linesize[1];
        const uint8_t *v = frame->data[2] + (ptrdiff_t)y * frame->linesize[2];
        for (int x = 0; x < (width + 1) / 2; ++x) {
            uvPlane[y * uvStride + 2 * x] = u[x];
            uvPlane[y * uvStride + 2 * x + 1] = v[x];
        }
    }
    CVPixelBufferUnlockBaseAddress(buffer, 0);
    CFStringRef matrix = frame->colorspace == AVCOL_SPC_BT709 ? kCVImageBufferYCbCrMatrix_ITU_R_709_2 :
        frame->colorspace == AVCOL_SPC_BT2020_NCL ? kCVImageBufferYCbCrMatrix_ITU_R_2020 :
        frame->colorspace == AVCOL_SPC_UNSPECIFIED && height > 576 ? kCVImageBufferYCbCrMatrix_ITU_R_709_2 : kCVImageBufferYCbCrMatrix_ITU_R_601_4;
    CVBufferSetAttachment(buffer, kCVImageBufferYCbCrMatrixKey, matrix, kCVAttachmentMode_ShouldPropagate);
    CVBufferSetAttachment(buffer, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2, kCVAttachmentMode_ShouldPropagate);
    CVBufferSetAttachment(buffer, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_ITU_R_709_2, kCVAttachmentMode_ShouldPropagate);
    CIImage *image = [CIImage imageWithCVPixelBuffer:buffer];
    if (frame->format == AV_PIX_FMT_YUVA420P) {
        NSMutableData *alpha = [NSMutableData dataWithLength:(NSUInteger)width * height];
        for (int y = 0; y < height; ++y) memcpy((uint8_t *)alpha.mutableBytes + y * width, frame->data[3] + (ptrdiff_t)y * frame->linesize[3], width);
        CIImage *mask = [CIImage imageWithBitmapData:alpha bytesPerRow:width size:CGSizeMake(width, height) format:kCIFormatL8 colorSpace:NULL];
        CIImage *clear = [[CIImage imageWithColor:[CIColor colorWithRed:0 green:0 blue:0 alpha:0]] imageByCroppingToRect:image.extent];
        image = [image imageByApplyingFilter:@"CIBlendWithMask" withInputParameters:@{kCIInputBackgroundImageKey: clear, kCIInputMaskImageKey: mask}];
    }
    if (isfinite(rotation) && fabs(rotation) > 0.001) image = [image imageByApplyingTransform:CGAffineTransformMakeRotation(-rotation)];
    CGFloat scale = MIN(1, 320.0 / MAX(image.extent.size.width, image.extent.size.height));
    image = [image imageByApplyingTransform:CGAffineTransformMakeScale(scale, scale)];
    static CIContext *context;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ context = [CIContext contextWithOptions:@{kCIContextUseSoftwareRenderer: @YES}]; });
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGImageRef cg = [context createCGImage:image fromRect:image.extent format:kCIFormatRGBA8 colorSpace:space];
    CGColorSpaceRelease(space);
    NSData *png = cg ? UIImagePNGRepresentation([UIImage imageWithCGImage:cg]) : nil;
    if (cg) CGImageRelease(cg);
    CVPixelBufferRelease(buffer);
    return png;
}

static BOOL Receive(FFMpegAVCodecContext *codec, FFMpegAVFrame *frame, BOOL (^consume)(FFMpegAVFrame *), NSError **error) {
    for (;;) {
        FFMpegAVCodecContextReceiveResult result = [codec receiveIntoFrame:frame];
        if (result == FFMpegAVCodecContextReceiveResultSuccess) {
            @autoreleasepool { if (!consume(frame)) return NO; }
        } else if (result == FFMpegAVCodecContextReceiveResultError) {
            MediaError(error, 2, @"FFmpeg не смог декодировать кадр.");
            return NO;
        } else return YES;
    }
}

@implementation FFMpegMedia
+ (FFMpegDecodedVideo *)decodeVideo:(NSString *)path maxDuration:(double)maxDuration error:(NSError **)error {
    if (!isfinite(maxDuration) || maxDuration <= 0) { MediaError(error, 1, @"Неверная длительность предпросмотра."); return nil; }
    [FFMpegGlobals initializeGlobals];
    FFMpegAVFormatContext *format = [[FFMpegAVFormatContext alloc] init];
    if (!format || ![format openInputWithDirectFilePath:path] || ![format findStreamInfo]) { MediaError(error, 1, @"FFmpeg не смог открыть видео."); return nil; }
    NSArray<NSNumber *> *videos = [format streamIndicesForType:FFMpegAVFormatStreamTypeVideo];
    int videoIndex = -1;
    for (NSNumber *number in videos) {
        if (![format isAttachedPicAtStreamIndex:number.intValue]) { videoIndex = number.intValue; break; }
    }
    if (videoIndex < 0) { MediaError(error, 1, @"В файле нет видеопотока."); return nil; }
    NSArray<NSNumber *> *audios = [format streamIndicesForType:FFMpegAVFormatStreamTypeAudio];
    int audioIndex = audios.count ? audios.firstObject.intValue : -1;
    FFMpegAVCodec *videoCodec = [FFMpegAVCodec findForId:[format codecIdAtStreamIndex:videoIndex] preferHardwareAccelerationCapable:NO];
    FFMpegAVCodecContext *video = videoCodec ? [[FFMpegAVCodecContext alloc] initWithCodec:videoCodec] : nil;
    if (!video || ![format codecParamsAtStreamIndex:videoIndex toContext:video] || ![video open]) { MediaError(error, 2, @"Видеокодек не поддерживается этой сборкой."); return nil; }
    FFMpegAVCodecContext *audio = nil;
    if (audioIndex >= 0) {
        FFMpegAVCodec *codec = [FFMpegAVCodec findForId:[format codecIdAtStreamIndex:audioIndex] preferHardwareAccelerationCapable:NO];
        audio = codec ? [[FFMpegAVCodecContext alloc] initWithCodec:codec] : nil;
        if (!audio || ![format codecParamsAtStreamIndex:audioIndex toContext:audio] || ![audio open]) { MediaError(error, 2, @"Аудиокодек не поддерживается этой сборкой."); return nil; }
    }
    FFMpegStreamMetrics metrics = [format metricsForStreamAtIndex:videoIndex];
    FFMpegFpsAndTimebase timing = [format fpsAndTimebaseForStreamIndex:videoIndex defaultTimeBase:CMTimeMake(1, 1000)];
    double videoBase = CMTimeGetSeconds(timing.timebase);
    double fps = CMTimeGetSeconds(timing.fps);
    if (!isfinite(fps) || fps <= 0) fps = 24;
    int64_t start = [format startTimeAtStreamIndex:videoIndex];
    __block int64_t origin = start;
    double audioBase = audio ? CMTimeGetSeconds([format fpsAndTimebaseForStreamIndex:audioIndex defaultTimeBase:CMTimeMake(1, 48000)].timebase) : 0;
    double limit = MIN(10, maxDuration);
    double duration = [format duration];
    // Container duration can end at the last frame PTS (not its end), or be rounded.
    // Use the caller limit for video; only trim audio padding to a known duration.
    double pcmDuration = isfinite(duration) && duration > 0 ? MIN(limit, duration) : limit;
    NSUInteger pcmLimit = (NSUInteger)ceil(pcmDuration * 48000) * 4;
    FFMpegDecodedVideo *result = [[FFMpegDecodedVideo alloc] init];
    result.width = metrics.width;
    result.height = metrics.height;
    result.framesPerSecond = fps;
    result.sourceDuration = duration;
    result.videoCodec = [NSString stringWithUTF8String:avcodec_get_name([format codecIdAtStreamIndex:videoIndex])];
    result.audioCodec = audio ? [NSString stringWithUTF8String:avcodec_get_name([format codecIdAtStreamIndex:audioIndex])] : @"нет";
    NSMutableArray<FFMpegPreviewFrame *> *frames = [NSMutableArray array];
    NSMutableData *pcm = [NSMutableData data];
    __block FFMpegSWResample *resampler = nil;
    __block NSError *consumeError = nil;
    __block BOOL audioStarted = NO, videoFinished = NO;
    __block NSUInteger audioLeadBytes = 0;
    __block double videoEnd = 0;
    BOOL (^consumeVideo)(FFMpegAVFrame *) = ^BOOL(FFMpegAVFrame *frame) {
        if (origin == AV_NOPTS_VALUE && frame.pts != AV_NOPTS_VALUE) origin = frame.pts;
        double time = frame.pts != AV_NOPTS_VALUE && origin != AV_NOPTS_VALUE ? (frame.pts - origin) * videoBase : result.videoFrameCount / fps;
        time = MAX(0, time);
        if (time >= limit) { videoFinished = YES; return YES; }
        result.videoFrameCount += 1;
        videoEnd = MIN(limit, time + (frame.duration > 0 ? frame.duration * videoBase : 1 / fps));
        if (frames.count && time - frames.lastObject.time < 1.0 / 30 - 0.00001) return YES;
        NSData *png = PreviewPNG(frame, metrics.rotationAngle);
        if (!png) { MediaError(&consumeError, 3, @"Предпросмотр поддерживает 8-битное YUV420-видео. Формат этого кадра не поддерживается."); return NO; }
        FFMpegPreviewFrame *preview = [[FFMpegPreviewFrame alloc] init];
        preview.time = time;
        preview.pngData = png;
        [frames addObject:preview];
        return YES;
    };
    BOOL (^consumeAudio)(FFMpegAVFrame *) = ^BOOL(FFMpegAVFrame *frame) {
        result.audioFrameCount += 1;
        if (!resampler) resampler = [[FFMpegSWResample alloc] initWithSourceChannelCount:audio.channels sourceSampleRate:audio.sampleRate sourceSampleFormat:audio.sampleFormat destinationChannelCount:2 destinationSampleRate:48000 destinationSampleFormat:FFMPEG_AV_SAMPLE_FMT_S16];
        NSData *data = [resampler resample:frame];
        if (!resampler || !data) { MediaError(&consumeError, 2, @"Не удалось получить PCM-аудио."); return NO; }
        if (!audioStarted) {
            double firstTime = frame.pts != AV_NOPTS_VALUE && origin != AV_NOPTS_VALUE ? frame.pts * audioBase - origin * videoBase : 0;
            if (firstTime > 0) pcm.length = MIN(pcmLimit, (NSUInteger)llround(MIN(firstTime, limit) * 48000) * 4);
            else if (firstTime < 0) audioLeadBytes = (NSUInteger)llround(MIN(-firstTime, 86400) * 48000) * 4;
            audioStarted = YES;
        }
        NSUInteger skip = MIN(audioLeadBytes, data.length);
        audioLeadBytes -= skip;
        if (pcm.length < pcmLimit) [pcm appendBytes:(const uint8_t *)data.bytes + skip length:MIN(data.length - skip, pcmLimit - pcm.length)];
        return YES;
    };
    FFMpegAVFrame *videoFrame = [[FFMpegAVFrame alloc] init], *audioFrame = [[FFMpegAVFrame alloc] init];
    FFMpegPacket *packet = [[FFMpegPacket alloc] init];
    if (!videoFrame || !audioFrame || !packet) { MediaError(error, 2, @"Не удалось выделить память для декодера."); return nil; }
    BOOL limited = NO;
    NSUInteger packets = 0;
    while ([format readFrameIntoPacket:packet]) {
        FFMpegAVCodecContext *codec = packet.streamIndex == videoIndex ? video : packet.streamIndex == audioIndex ? audio : nil;
        if (codec) {
            FFMpegAVFrame *frame = codec == video ? videoFrame : audioFrame;
            BOOL (^consume)(FFMpegAVFrame *) = codec == video ? consumeVideo : consumeAudio;
            int status = [packet sendToDecoder:codec];
            if (status == AVERROR(EAGAIN)) {
                if (!Receive(codec, frame, consume, error)) { if (consumeError && error) *error = consumeError; return nil; }
                status = [packet sendToDecoder:codec];
            }
            if (status < 0 || !Receive(codec, frame, consume, error)) { if (status < 0) MediaError(error, 2, @"Декодер отклонил пакет."); else if (consumeError && error) *error = consumeError; return nil; }
        }
        if ((videoFinished && (!audio || pcm.length >= pcmLimit)) || ++packets >= 100000) { limited = YES; break; }
    }
    if (!limited && format.lastReadError != AVERROR_EOF) { MediaError(error, 2, @"Ошибка чтения медиаданных."); return nil; }
    if (![video sendEnd] || !Receive(video, videoFrame, consumeVideo, error)) { if (consumeError && error) *error = consumeError; else MediaError(error, 2, @"Не удалось завершить декодирование видео."); return nil; }
    if (audio && (![audio sendEnd] || !Receive(audio, audioFrame, consumeAudio, error))) { if (consumeError && error) *error = consumeError; else MediaError(error, 2, @"Не удалось завершить декодирование аудио."); return nil; }
    if (resampler) {
        NSData *tail;
        while ((tail = [resampler drain])) {
            if (pcm.length < pcmLimit) [pcm appendBytes:tail.bytes length:MIN(tail.length, pcmLimit - pcm.length)];
        }
    }
    if (!frames.count) { MediaError(error, 2, @"FFmpeg не вернул видеокадры."); return nil; }
    result.frames = frames;
    result.pcmData = pcm;
    result.previewDuration = MIN(limit, MAX(videoEnd, pcm.length / (48000.0 * 4)));
    return result;
}
@end
