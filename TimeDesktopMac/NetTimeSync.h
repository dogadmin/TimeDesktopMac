#import <Foundation/Foundation.h>

@interface NetTimeSync : NSObject

@property (nonatomic, readonly) NSTimeInterval offsetSeconds;

+ (instancetype)shared;
- (NSDate *)correctedNow;
- (void)startSync;
- (void)stopSync;

@end
