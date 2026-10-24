#import "ObjCPlugin.h"

@implementation ObjCPlugin

+ (NSString *)message {
    return @"Objective-C plugin OK";
}

+ (NSInteger)subtract:(NSInteger)lhs from:(NSInteger)rhs {
    return rhs - lhs;
}

@end
