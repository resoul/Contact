#import <FFMpegBinding/FFMpegRemuxer.h>
#import "FFMpegRemux.h"

@implementation FFMpegRemuxer
+ (bool)remux:(NSString *)path to:(NSString *)outPath {
    return FFMpegRemuxFile(path, outPath, NO, 0);
}
@end
