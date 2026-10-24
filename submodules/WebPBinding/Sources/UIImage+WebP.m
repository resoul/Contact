#import <WebPBinding/UIImage+WebP.h>

#import <webp/decode.h>
#import <webp/encode.h>

#include <limits.h>
#include <math.h>
#include <stdint.h>
#include <stdlib.h>

NSErrorDomain const WebPErrorDomain = @"org.airlance.Contact.WebP";

static void SetError(NSError **error, WebPErrorCode code, NSString *message) {
    if (error != NULL) {
        *error = [NSError errorWithDomain:WebPErrorDomain
                                    code:code
                                userInfo:@{NSLocalizedDescriptionKey: message}];
    }
}

static BOOL PixelBufferSize(size_t width, size_t height, size_t *stride, size_t *size) {
    if (width == 0 || height == 0 || width > WEBP_MAX_DIMENSION || height > WEBP_MAX_DIMENSION) {
        return NO;
    }
    *stride = width * 4;
    if (*stride > INT_MAX || height > SIZE_MAX / *stride) {
        return NO;
    }
    *size = height * *stride;
    return YES;
}

static void ReleasePixels(void *info, const void *data, size_t size) {
    free((void *)data);
}

static NSData *Encode(UIImage *image, CGFloat quality, BOOL lossless, NSError **error) {
    if (!isfinite(quality) || quality < 0 || quality > 100) {
        SetError(error, WebPErrorInvalidQuality, @"WebP quality must be between 0 and 100.");
        return nil;
    }
    CGImageRef source = image.CGImage;
    if (source == NULL) {
        SetError(error, WebPErrorInvalidImage, @"A CGImage-backed UIImage is required.");
        return nil;
    }

    size_t width = CGImageGetWidth(source);
    size_t height = CGImageGetHeight(source);
    switch (image.imageOrientation) {
        case UIImageOrientationLeft:
        case UIImageOrientationLeftMirrored:
        case UIImageOrientationRight:
        case UIImageOrientationRightMirrored: {
            size_t swap = width;
            width = height;
            height = swap;
            break;
        }
        default:
            break;
    }
    size_t stride, size;
    if (!PixelBufferSize(width, height, &stride, &size)) {
        SetError(error, WebPErrorInvalidImage, @"Image dimensions exceed WebP limits.");
        return nil;
    }

    __attribute__((objc_precise_lifetime)) UIImage *normalized = image;
    if (image.imageOrientation != UIImageOrientationUp) {
        UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
        format.scale = 1;
        format.opaque = NO;
        format.preferredRange = UIGraphicsImageRendererFormatRangeStandard;
        UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc]
            initWithSize:CGSizeMake(width, height) format:format];
        normalized = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
            [image drawInRect:CGRectMake(0, 0, width, height)];
        }];
        source = normalized.CGImage;
    }

    uint8_t *pixels = calloc(1, size);
    if (pixels == NULL) {
        SetError(error, WebPErrorAllocationFailed, @"Unable to allocate image pixels.");
        return nil;
    }
    CGColorSpaceRef colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    if (colorSpace == NULL) {
        free(pixels);
        SetError(error, WebPErrorAllocationFailed, @"Unable to create the sRGB color space.");
        return nil;
    }
    CGContextRef context = CGBitmapContextCreate(pixels, width, height, 8, stride, colorSpace,
        (CGBitmapInfo)kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(colorSpace);
    if (context == NULL) {
        free(pixels);
        SetError(error, WebPErrorAllocationFailed, @"Unable to create an image context.");
        return nil;
    }
    CGContextSetBlendMode(context, kCGBlendModeCopy);
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), source);
    CGContextRelease(context);

    for (size_t i = 0; i < size; i += 4) {
        unsigned alpha = pixels[i + 3];
        for (size_t channel = 0; channel < 3; ++channel) {
            unsigned value = alpha == 0 ? 0 : (pixels[i + channel] * 255u + alpha / 2) / alpha;
            pixels[i + channel] = (uint8_t)MIN(value, 255u);
        }
    }

    WebPConfig config;
    if (!WebPConfigInit(&config)) {
        free(pixels);
        SetError(error, WebPErrorEncodingFailed, @"Unable to initialize the WebP encoder.");
        return nil;
    }
    config.quality = (float)quality;
    config.lossless = lossless;
    config.method = 6;
    config.thread_level = 1;
    config.use_sharp_yuv = 1;
    config.exact = 1;
    if (!WebPValidateConfig(&config)) {
        free(pixels);
        SetError(error, WebPErrorEncodingFailed, @"Invalid WebP encoder configuration.");
        return nil;
    }

    WebPPicture picture;
    if (!WebPPictureInit(&picture)) {
        free(pixels);
        SetError(error, WebPErrorEncodingFailed, @"Unable to initialize the WebP picture.");
        return nil;
    }
    picture.width = (int)width;
    picture.height = (int)height;
    picture.use_argb = 1;
    BOOL imported = WebPPictureImportRGBA(&picture, pixels, (int)stride);
    free(pixels);
    if (!imported) {
        WebPPictureFree(&picture);
        SetError(error, WebPErrorAllocationFailed, @"Unable to import pixels into WebP.");
        return nil;
    }

    WebPMemoryWriter writer;
    WebPMemoryWriterInit(&writer);
    picture.writer = WebPMemoryWrite;
    picture.custom_ptr = &writer;
    BOOL encoded = WebPEncode(&config, &picture);
    WebPEncodingError encodingError = picture.error_code;
    WebPPictureFree(&picture);
    NSData *result = nil;
    if (encoded) {
        result = [NSData dataWithBytes:writer.mem length:writer.size];
    } else {
        SetError(error, WebPErrorEncodingFailed,
            [NSString stringWithFormat:@"WebP encoding failed (code %d).", encodingError]);
    }
    WebPMemoryWriterClear(&writer);
    return result;
}

@implementation WebP

+ (UIImage *)convertFromWebP:(NSData *)data {
    WebPDecoderConfig config;
    if (!WebPInitDecoderConfig(&config) ||
        WebPGetFeatures(data.bytes, data.length, &config.input) != VP8_STATUS_OK ||
        config.input.has_animation) {
        return nil;
    }
    size_t width = config.input.width;
    size_t height = config.input.height;
    size_t stride, size;
    if (!PixelBufferSize(width, height, &stride, &size)) {
        return nil;
    }
    uint8_t *pixels = malloc(size);
    if (pixels == NULL) {
        return nil;
    }

    config.output.colorspace = MODE_rgbA;
    config.output.is_external_memory = 1;
    config.output.u.RGBA.rgba = pixels;
    config.output.u.RGBA.stride = (int)stride;
    config.output.u.RGBA.size = size;
    config.options.use_threads = 1;
    VP8StatusCode status = WebPDecode(data.bytes, data.length, &config);
    WebPFreeDecBuffer(&config.output);
    if (status != VP8_STATUS_OK) {
        free(pixels);
        return nil;
    }

    CGDataProviderRef provider = CGDataProviderCreateWithData(NULL, pixels, size, ReleasePixels);
    if (provider == NULL) {
        free(pixels);
        return nil;
    }
    CGColorSpaceRef colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    if (colorSpace == NULL) {
        CGDataProviderRelease(provider);
        return nil;
    }
    CGImageRef cgImage = CGImageCreate(width, height, 8, 32, stride, colorSpace,
        (CGBitmapInfo)kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big, provider, NULL, NO,
        kCGRenderingIntentDefault);
    CGColorSpaceRelease(colorSpace);
    CGDataProviderRelease(provider);
    if (cgImage == NULL) {
        return nil;
    }
    UIImage *image = [UIImage imageWithCGImage:cgImage scale:1 orientation:UIImageOrientationUp];
    CGImageRelease(cgImage);
    return image;
}

+ (NSData *)convertToWebP:(UIImage *)image quality:(CGFloat)quality error:(NSError **)error {
    return Encode(image, quality, NO, error);
}

+ (NSData *)convertToLosslessWebP:(UIImage *)image error:(NSError **)error {
    return Encode(image, 100, YES, error);
}

@end
