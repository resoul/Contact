#import <FFMpegBinding/FFMpegGlobals.h>

#import "libavformat/avformat.h"

@implementation FFMpegGlobals

+ (NSString *)version { return [NSString stringWithUTF8String:av_version_info()]; }

+ (void)initializeGlobals {
#if DEBUG
    av_log_set_level(AV_LOG_ERROR);
#else
    av_log_set_level(AV_LOG_QUIET);
#endif
}

@end
