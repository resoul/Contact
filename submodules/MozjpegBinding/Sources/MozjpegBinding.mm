// Adapted from Telegram-iOS MozjpegBinding; see README for provenance.
#import <MozjpegBinding/MozjpegBinding.h>
#include <stdio.h>
#include <setjmp.h>
#include <math.h>
#include <limits.h>
#include <mozjpeg/jpeglib.h>
#include <mozjpeg/turbojpeg.h>
#include <jxl/encode.h>
#include <jxl/decode.h>
#include <jxl/cms.h>
#include <memory>

NSErrorDomain const MozjpegErrorDomain = @"org.airlance.Contact.Mozjpeg";
static const size_t MaxPixels = 32000000;
static const size_t MaxEncodedBytes = 256 * 1024 * 1024;

static void Fail(NSError **error, MozjpegErrorCode code, NSString *message) {
    if (error) *error = [NSError errorWithDomain:MozjpegErrorDomain code:code
                                      userInfo:@{NSLocalizedDescriptionKey: message}];
}
static BOOL ValidSize(size_t width, size_t height) {
    return width && height && width <= JPEG_MAX_DIMENSION && height <= JPEG_MAX_DIMENSION &&
        width <= MaxPixels / height;
}

// Produces upright 8-bit sRGB, with either straight alpha or a white background.
static NSData *Pixels(UIImage *image, BOOL alpha, CGSize limit, size_t *width, size_t *height) {
    CGImageRef source = image.CGImage;
    if (!source) return nil;
    size_t w = CGImageGetWidth(source), h = CGImageGetHeight(source);
    if (image.imageOrientation == UIImageOrientationLeft || image.imageOrientation == UIImageOrientationRight ||
        image.imageOrientation == UIImageOrientationLeftMirrored || image.imageOrientation == UIImageOrientationRightMirrored) {
        size_t swap = w; w = h; h = swap;
    }
    if (!ValidSize(w, h)) return nil;
    if (limit.width > 0 && limit.height > 0) {
        double scale = MIN(1.0, MIN(limit.width / w, limit.height / h));
        w = MAX(1, (size_t)floor(w * scale)); h = MAX(1, (size_t)floor(h * scale));
    }
    __attribute__((objc_precise_lifetime)) UIImage *normalized = image;
    if (image.imageOrientation != UIImageOrientationUp) {
        UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
        format.scale = 1; format.opaque = NO;
        format.preferredRange = UIGraphicsImageRendererFormatRangeStandard;
        UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(w, h) format:format];
        normalized = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
            [image drawInRect:CGRectMake(0, 0, w, h)];
        }];
        source = normalized.CGImage;
    }
    NSMutableData *pixels = [NSMutableData dataWithLength:w * h * 4];
    CGColorSpaceRef color = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    if (!color) return nil;
    CGContextRef context = CGBitmapContextCreate(pixels.mutableBytes, w, h, 8, w * 4, color,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(color);
    if (!context) return nil;
    if (!alpha) {
        CGContextSetRGBFillColor(context, 1, 1, 1, 1);
        CGContextFillRect(context, CGRectMake(0, 0, w, h));
    }
    CGContextDrawImage(context, CGRectMake(0, 0, w, h), source);
    CGContextRelease(context);
    if (alpha) {
        uint8_t *p = (uint8_t *)pixels.mutableBytes;
        for (size_t i = 0; i < pixels.length; i += 4) {
            unsigned a = p[i + 3];
            for (size_t c = 0; c < 3; ++c) p[i + c] = a ? MIN(255u, (p[i + c] * 255u + a / 2) / a) : 0;
        }
    }
    *width = w; *height = h;
    return pixels;
}

static UIImage *ImageFromRGBA(NSData *data, size_t width, size_t height, BOOL straightAlpha) {
    NSMutableData *pixels = [data mutableCopy];
    if (straightAlpha) {
        uint8_t *p = (uint8_t *)pixels.mutableBytes;
        for (size_t i = 0; i < pixels.length; i += 4)
            for (size_t c = 0; c < 3; ++c) p[i + c] = (p[i + c] * p[i + 3] + 127) / 255;
    }
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)pixels);
    CGColorSpaceRef color = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    if (!provider || !color) {
        if (provider) CGDataProviderRelease(provider);
        if (color) CGColorSpaceRelease(color);
        return nil;
    }
    CGImageRef cg = CGImageCreate(width, height, 8, 32, width * 4, color,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big, provider, NULL, false, kCGRenderingIntentDefault);
    CGDataProviderRelease(provider); CGColorSpaceRelease(color);
    if (!cg) return nil;
    UIImage *image = [UIImage imageWithCGImage:cg];
    CGImageRelease(cg);
    return image;
}

struct JPEGError {
    jpeg_error_mgr manager;
    jmp_buf jump;
    char message[JMSG_LENGTH_MAX];
};
struct JPEGState {
    jpeg_compress_struct codec;
    JPEGError error;
    unsigned char *output;
    unsigned long length;
};
static void JPEGErrorExit(j_common_ptr codec) {
    JPEGError *error = (JPEGError *)codec->err;
    (*codec->err->format_message)(codec, error->message);
    longjmp(error->jump, 1);
}

static NSData *EncodeJPEG(NSData *pixels, size_t width, size_t height, int quality,
                          BOOL progressive, BOOL fast, BOOL optimize, NSError **error) {
    // State changed after setjmp lives on the heap. No C++/ARC scope is crossed by longjmp.
    JPEGState *state = (JPEGState *)calloc(1, sizeof(JPEGState));
    if (!state) { Fail(error, MozjpegErrorAllocationFailed, @"Unable to allocate JPEG encoder."); return nil; }
    state->codec.err = jpeg_std_error(&state->error.manager);
    state->error.manager.error_exit = JPEGErrorExit;
    if (setjmp(state->error.jump)) {
        NSString *message = [NSString stringWithUTF8String:state->error.message];
        jpeg_destroy_compress(&state->codec); free(state->output); free(state);
        Fail(error, MozjpegErrorEncodingFailed, message ?: @"JPEG encoding failed.");
        return nil;
    }
    jpeg_create_compress(&state->codec);
    jpeg_mem_dest(&state->codec, &state->output, &state->length);
    state->codec.image_width = (JDIMENSION)width;
    state->codec.image_height = (JDIMENSION)height;
    state->codec.input_components = 4;
    state->codec.in_color_space = JCS_EXT_RGBX;
    jpeg_c_set_int_param(&state->codec, JINT_COMPRESS_PROFILE, fast ? JCP_FASTEST : JCP_MAX_COMPRESSION);
    jpeg_set_defaults(&state->codec);
    state->codec.arith_code = FALSE;
    state->codec.dct_method = JDCT_ISLOW;
    state->codec.optimize_coding = optimize;
    jpeg_set_quality(&state->codec, quality, TRUE);
    if (progressive) jpeg_simple_progression(&state->codec);
    else { state->codec.scan_info = NULL; state->codec.num_scans = 0; }
    jpeg_start_compress(&state->codec, TRUE);
    while (state->codec.next_scanline < state->codec.image_height) {
        JSAMPROW row = (JSAMPROW)((const uint8_t *)pixels.bytes + state->codec.next_scanline * width * 4);
        jpeg_write_scanlines(&state->codec, &row, 1);
    }
    jpeg_finish_compress(&state->codec);
    NSData *result = [NSData dataWithBytes:state->output length:state->length];
    jpeg_destroy_compress(&state->codec); free(state->output); free(state);
    return result;
}

@implementation MozJPEG
+ (NSData *)encode:(UIImage *)image quality:(NSInteger)quality progressive:(BOOL)progressive fast:(BOOL)fast error:(NSError **)error {
    if (quality < 0 || quality > 100) { Fail(error, MozjpegErrorInvalidInput, @"JPEG quality must be 0–100."); return nil; }
    size_t width, height;
    NSData *pixels = Pixels(image, NO, CGSizeZero, &width, &height);
    if (!pixels) { Fail(error, MozjpegErrorInvalidInput, @"Invalid image or image exceeds 32 million pixels."); return nil; }
    return EncodeJPEG(pixels, width, height, (int)quality, progressive, fast, YES, error);
}
+ (UIImage *)decode:(NSData *)data error:(NSError **)error {
    if (!data.length || data.length > MaxEncodedBytes) { Fail(error, MozjpegErrorInvalidInput, @"Invalid JPEG input size."); return nil; }
    tjhandle decoder = tjInitDecompress();
    if (!decoder) { Fail(error, MozjpegErrorAllocationFailed, @"Unable to allocate JPEG decoder."); return nil; }
    int width = 0, height = 0, subsampling = 0, colorspace = 0;
    BOOL valid = tjDecompressHeader3(decoder, (const unsigned char *)data.bytes, data.length,
        &width, &height, &subsampling, &colorspace) == 0 && width > 0 && height > 0 && ValidSize(width, height);
    NSMutableData *pixels = valid ? [NSMutableData dataWithLength:(size_t)width * height * 4] : nil;
    if (valid) valid = tjDecompress2(decoder, (const unsigned char *)data.bytes, data.length,
        (unsigned char *)pixels.mutableBytes, width, width * 4, height, TJPF_RGBA, TJFLAG_STOPONWARNING) == 0;
    NSString *message = valid ? nil : [NSString stringWithUTF8String:tjGetErrorStr2(decoder)];
    tjDestroy(decoder);
    if (!valid) { Fail(error, MozjpegErrorDecodingFailed, message ?: @"Invalid JPEG or image dimensions."); return nil; }
    return ImageFromRGBA(pixels, width, height, NO);
}

+ (NSData *)encodeXL:(UIImage *)image quality:(NSInteger)quality error:(NSError **)error {
    if (quality < 0 || quality > 100) { Fail(error, MozjpegErrorInvalidInput, @"JPEG XL quality must be 0–100."); return nil; }
    size_t width, height;
    NSData *pixels = Pixels(image, YES, CGSizeZero, &width, &height);
    if (!pixels) { Fail(error, MozjpegErrorInvalidInput, @"Invalid image or image exceeds 32 million pixels."); return nil; }
    std::unique_ptr<JxlEncoder, decltype(&JxlEncoderDestroy)> enc(JxlEncoderCreate(NULL), JxlEncoderDestroy);
    if (!enc) { Fail(error, MozjpegErrorAllocationFailed, @"Unable to allocate JPEG XL encoder."); return nil; }
    JxlBasicInfo info; JxlEncoderInitBasicInfo(&info);
    info.xsize = (uint32_t)width; info.ysize = (uint32_t)height;
    info.bits_per_sample = 8; info.exponent_bits_per_sample = 0;
    info.num_color_channels = 3; info.num_extra_channels = 1;
    info.alpha_bits = 8; info.alpha_premultiplied = JXL_FALSE;
    info.uses_original_profile = quality == 100 ? JXL_TRUE : JXL_FALSE;
    JxlColorEncoding color; JxlColorEncodingSetToSRGB(&color, JXL_FALSE);
    JxlEncoderFrameSettings *settings = JxlEncoderFrameSettingsCreate(enc.get(), NULL);
    const JxlPixelFormat format = {4, JXL_TYPE_UINT8, JXL_NATIVE_ENDIAN, 0};
    // Preserve Telegram's quality-to-distance mapping; 100 adds true lossless mode.
    float distance = quality == 0 ? 1.0f : quality >= 30 ? 0.1f + (100 - quality) * 0.09f :
        6.24f + (float)pow(2.5, (30.0 - quality) / 5.0) / 6.25f;
    if (!settings || JxlEncoderSetBasicInfo(enc.get(), &info) != JXL_ENC_SUCCESS ||
        JxlEncoderSetColorEncoding(enc.get(), &color) != JXL_ENC_SUCCESS ||
        JxlEncoderSetFrameDistance(settings, quality == 100 ? 0 : distance) != JXL_ENC_SUCCESS ||
        JxlEncoderSetFrameLossless(settings, quality == 100 ? JXL_TRUE : JXL_FALSE) != JXL_ENC_SUCCESS ||
        JxlEncoderFrameSettingsSetOption(settings, JXL_ENC_FRAME_SETTING_EFFORT, 8) != JXL_ENC_SUCCESS ||
        JxlEncoderAddImageFrame(settings, &format, pixels.bytes, pixels.length) != JXL_ENC_SUCCESS) {
        Fail(error, MozjpegErrorEncodingFailed, @"Unable to configure JPEG XL encoder."); return nil;
    }
    JxlEncoderCloseInput(enc.get());
    NSMutableData *result = [NSMutableData dataWithLength:4096];
    size_t used = 0;
    while (true) {
        uint8_t *next = (uint8_t *)result.mutableBytes + used;
        size_t available = result.length - used;
        JxlEncoderStatus status = JxlEncoderProcessOutput(enc.get(), &next, &available);
        used = result.length - available;
        if (status == JXL_ENC_SUCCESS) { result.length = used; return result; }
        if (status != JXL_ENC_NEED_MORE_OUTPUT || result.length >= MaxEncodedBytes) {
            Fail(error, MozjpegErrorEncodingFailed, @"JPEG XL encoding failed or output exceeds 256 MiB."); return nil;
        }
        result.length = MIN(MaxEncodedBytes, result.length * 2);
    }
}

+ (UIImage *)decodeXL:(NSData *)data error:(NSError **)error {
    if (!data.length || data.length > MaxEncodedBytes) { Fail(error, MozjpegErrorInvalidInput, @"Invalid JPEG XL input size."); return nil; }
    std::unique_ptr<JxlDecoder, decltype(&JxlDecoderDestroy)> dec(JxlDecoderCreate(NULL), JxlDecoderDestroy);
    if (!dec) { Fail(error, MozjpegErrorAllocationFailed, @"Unable to allocate JPEG XL decoder."); return nil; }
    if (JxlDecoderSetCms(dec.get(), *JxlGetDefaultCms()) != JXL_DEC_SUCCESS ||
        JxlDecoderSubscribeEvents(dec.get(), JXL_DEC_BASIC_INFO | JXL_DEC_COLOR_ENCODING | JXL_DEC_FULL_IMAGE) != JXL_DEC_SUCCESS ||
        JxlDecoderSetUnpremultiplyAlpha(dec.get(), JXL_TRUE) != JXL_DEC_SUCCESS ||
        JxlDecoderSetInput(dec.get(), (const uint8_t *)data.bytes, data.length) != JXL_DEC_SUCCESS) {
        Fail(error, MozjpegErrorDecodingFailed, @"Unable to configure JPEG XL decoder."); return nil;
    }
    JxlDecoderCloseInput(dec.get());
    JxlBasicInfo info = {};
    const JxlPixelFormat format = {4, JXL_TYPE_UINT8, JXL_NATIVE_ENDIAN, 0};
    NSMutableData *pixels = nil;
    BOOL completed = NO;
    while (true) {
        JxlDecoderStatus status = JxlDecoderProcessInput(dec.get());
        if (status == JXL_DEC_BASIC_INFO) {
            if (JxlDecoderGetBasicInfo(dec.get(), &info) != JXL_DEC_SUCCESS || !ValidSize(info.xsize, info.ysize) || info.have_animation) break;
        } else if (status == JXL_DEC_COLOR_ENCODING) {
            JxlColorEncoding color; JxlColorEncodingSetToSRGB(&color, JXL_FALSE);
            if (JxlDecoderSetOutputColorProfile(dec.get(), &color, NULL, 0) != JXL_DEC_SUCCESS) break;
        } else if (status == JXL_DEC_NEED_IMAGE_OUT_BUFFER) {
            size_t size = 0;
            if (!ValidSize(info.xsize, info.ysize) ||
                JxlDecoderImageOutBufferSize(dec.get(), &format, &size) != JXL_DEC_SUCCESS ||
                size != (size_t)info.xsize * info.ysize * 4) break;
            pixels = [NSMutableData dataWithLength:size];
            if (JxlDecoderSetImageOutBuffer(dec.get(), &format, pixels.mutableBytes, size) != JXL_DEC_SUCCESS) break;
        } else if (status == JXL_DEC_FULL_IMAGE) {
            completed = YES;
        } else if (status == JXL_DEC_SUCCESS) {
            if (completed && pixels) return ImageFromRGBA(pixels, info.xsize, info.ysize, YES);
            break;
        } else break;
    }
    Fail(error, MozjpegErrorDecodingFailed, @"Invalid, truncated, oversized, or animated JPEG XL image.");
    return nil;
}
@end

NSData *compressJPEGData(UIImage *image, __unused NSString *tempFilePath) {
    return [MozJPEG encode:image quality:72 progressive:YES fast:YES error:NULL];
}
UIImage *decompressImage(NSData *data) { return [MozJPEG decode:data error:NULL]; }
NSData *compressJPEGXLData(UIImage *image, int quality) { return [MozJPEG encodeXL:image quality:quality error:NULL]; }
UIImage *decompressJPEGXLData(NSData *data) { return [MozJPEG decodeXL:data error:NULL]; }

NSArray<NSNumber *> *extractJPEGDataScans(NSData *data) {
    const uint8_t *bytes = (const uint8_t *)data.bytes;
    size_t n = data.length, p = 2;
    if (n < 4 || n > MaxEncodedBytes || bytes[0] != 0xff || bytes[1] != 0xd8) return @[];
    NSMutableArray<NSNumber *> *scans = [NSMutableArray array];
    BOOL entropy = NO, first = YES;
    while (p < n) {
        if (entropy) {
            while (p < n) {
                if (bytes[p] != 0xff) { ++p; continue; }
                size_t next = p + 1;
                while (next < n && bytes[next] == 0xff) ++next;
                if (next >= n) return @[];
                if (bytes[next] == 0 || (bytes[next] >= 0xd0 && bytes[next] <= 0xd7)) { p = next + 1; continue; }
                break;
            }
        }
        if (p >= n || bytes[p] != 0xff) return @[];
        size_t start = p;
        while (p < n && bytes[p] == 0xff) ++p;
        if (p >= n) return @[];
        uint8_t marker = bytes[p++];
        if (marker == 0xd9) return first ? @[] : scans;
        if (marker == 0 || marker == 0xd8 || (marker >= 0xd0 && marker <= 0xd7)) return @[];
        if (marker == 1) continue;
        if (n - p < 2) return @[];
        size_t length = (bytes[p] << 8) | bytes[p + 1];
        if (length < 2 || length > n - p) return @[];
        entropy = marker == 0xda;
        if (entropy) {
            if (length < 6) return @[];
            if (!first) [scans addObject:@(start)];
            first = NO;
        }
        p += length;
    }
    return @[];
}

static NSData *ThumbnailHeader() {
    static NSData *header;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ header = [[NSData alloc] initWithBase64EncodedString:@"/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDACgcHiMeGSgjISMtKygwPGRBPDc3PHtYXUlkkYCZlo+AjIqgtObDoKrarYqMyP/L2u71////m8H////6/+b9//j/2wBDASstLTw1PHZBQXb4pYyl+Pj4+Pj4+Pj4+Pj4+Pj4+Pj4+Pj4+Pj4+Pj4+Pj4+Pj4+Pj4+Pj4+Pj4+Pj4+Pj4+Pj/wAARCAAAAAADASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwA=" options:0]; });
    return header;
}

NSData *compressMiniThumbnail(UIImage *image, CGSize size) {
    if (!isfinite(size.width) || !isfinite(size.height) || size.width < 1 || size.height < 1 ||
        size.width > 255 || size.height > 255) return nil;
    size_t width, height;
    NSData *pixels = Pixels(image, NO, size, &width, &height);
    if (!pixels || width > 255 || height > 255) return nil;
    NSData *jpeg = EncodeJPEG(pixels, width, height, 20, NO, YES, NO, NULL);
    NSData *header = ThumbnailHeader();
    if (!jpeg || jpeg.length <= header.length + 2) return nil;
    NSMutableData *prefix = [[jpeg subdataWithRange:NSMakeRange(0, header.length)] mutableCopy];
    uint8_t *bytes = (uint8_t *)prefix.mutableBytes;
    const uint8_t *full = (const uint8_t *)jpeg.bytes;
    if (bytes[164] != height || bytes[166] != width || full[jpeg.length - 2] != 0xff || full[jpeg.length - 1] != 0xd9) return nil;
    bytes[164] = 0; bytes[166] = 0;
    if (![prefix isEqualToData:header]) return nil;
    const uint8_t dimensions[] = {1, (uint8_t)height, (uint8_t)width};
    NSMutableData *result = [NSMutableData dataWithBytes:dimensions length:3];
    [result appendData:[jpeg subdataWithRange:NSMakeRange(header.length, jpeg.length - header.length - 2)]];
    return result;
}

NSData *decodeTinyThumbnail(NSData *data) {
    if (data.length <= 3 || data.length > MaxEncodedBytes) return nil;
    const uint8_t *bytes = (const uint8_t *)data.bytes;
    if (bytes[0] != 1 || !bytes[1] || !bytes[2]) return nil;
    NSMutableData *result = [ThumbnailHeader() mutableCopy];
    uint8_t *header = (uint8_t *)result.mutableBytes;
    header[164] = bytes[1]; header[166] = bytes[2];
    [result appendData:[data subdataWithRange:NSMakeRange(3, data.length - 3)]];
    const uint8_t footer[] = {0xff, 0xd9};
    [result appendBytes:footer length:2];
    return result;
}
