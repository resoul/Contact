#import <FFMpegBinding/FFMpegLiveMuxer.h>
#import "FFMpegRemux.h"

@implementation FFMpegLiveMuxer
+ (bool)remux:(NSString *)path to:(NSString *)outPath offsetSeconds:(double)offsetSeconds {
    return FFMpegRemuxFile(path, outPath, YES, offsetSeconds);
}
@end
