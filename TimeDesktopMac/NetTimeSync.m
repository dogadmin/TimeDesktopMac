#import "NetTimeSync.h"
#import <os/lock.h>

@implementation NetTimeSync {
    NSTimer *_timer;
    NSURLSession *_session;
    NSTimeInterval _offset;
    os_unfair_lock _lock;
}

+ (instancetype)shared {
    static NetTimeSync *inst;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ inst = [[NetTimeSync alloc] init]; });
    return inst;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _offset = 0;
        _lock = OS_UNFAIR_LOCK_INIT;
        NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        cfg.timeoutIntervalForRequest = 3.0;
        cfg.timeoutIntervalForResource = 5.0;
        _session = [NSURLSession sessionWithConfiguration:cfg];
    }
    return self;
}

- (NSTimeInterval)offsetSeconds {
    os_unfair_lock_lock(&_lock);
    NSTimeInterval v = _offset;
    os_unfair_lock_unlock(&_lock);
    return v;
}

- (NSDate *)correctedNow {
    return [NSDate dateWithTimeIntervalSinceNow:self.offsetSeconds];
}

- (void)setOffset:(NSTimeInterval)v {
    os_unfair_lock_lock(&_lock);
    _offset = v;
    os_unfair_lock_unlock(&_lock);
}

- (void)startSync {
    [self doSync];
    _timer = [NSTimer scheduledTimerWithTimeInterval:600.0
                                              target:self
                                            selector:@selector(doSync)
                                            userInfo:nil
                                             repeats:YES];
    _timer.tolerance = 30.0;
}

- (void)stopSync {
    [_timer invalidate];
    _timer = nil;
}

- (void)doSync {
    [self fetchWorldTimeAPI:^(BOOL ok) {
        if (!ok) {
            [self fetchGoogleDate];
        }
    }];
}

- (void)fetchWorldTimeAPI:(void(^)(BOOL ok))completion {
    NSURL *url = [NSURL URLWithString:@"https://worldtimeapi.org/api/timezone/Etc/UTC"];
    NSDate *before = [NSDate date];
    [[_session dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        if (err || !data) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(NO); });
            return;
        }
        NSError *jsonErr;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonErr];
        if (jsonErr || !json[@"utc_datetime"]) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(NO); });
            return;
        }
        NSString *utcStr = json[@"utc_datetime"];
        NSISO8601DateFormatter *fmt = [[NSISO8601DateFormatter alloc] init];
        fmt.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;
        NSDate *serverTime = [fmt dateFromString:utcStr];
        if (!serverTime) {
            fmt.formatOptions = NSISO8601DateFormatWithInternetDateTime;
            serverTime = [fmt dateFromString:utcStr];
        }
        if (serverTime) {
            NSTimeInterval rtt = [[NSDate date] timeIntervalSinceDate:before];
            NSDate *adjusted = [serverTime dateByAddingTimeInterval:rtt / 2.0];
            [self setOffset:[adjusted timeIntervalSinceNow]];
            dispatch_async(dispatch_get_main_queue(), ^{ completion(YES); });
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(NO); });
        }
    }] resume];
}

- (void)fetchGoogleDate {
    NSURL *url = [NSURL URLWithString:@"https://www.google.com/generate_204"];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"HEAD";
    [[_session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        if (err) return;
        NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)resp;
        NSString *dateStr = httpResp.allHeaderFields[@"Date"];
        if (!dateStr) return;
        NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
        fmt.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
        fmt.dateFormat = @"EEE, dd MMM yyyy HH:mm:ss zzz";
        fmt.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"GMT"];
        NSDate *serverTime = [fmt dateFromString:dateStr];
        if (serverTime) {
            [self setOffset:[serverTime timeIntervalSinceNow]];
        }
    }] resume];
}

@end
