#import <Foundation/Foundation.h>

@interface TZCity : NSObject
@property (nonatomic, copy) NSString *tz;
@property (nonatomic, copy) NSString *en;
@property (nonatomic, copy) NSString *cn;
+ (instancetype)cityWithTZ:(NSString *)tz en:(NSString *)en cn:(NSString *)cn;
@end

@interface TZRegion : NSObject
@property (nonatomic, copy) NSString *en;
@property (nonatomic, copy) NSString *cn;
@property (nonatomic, strong) NSArray<TZCity *> *cities;
+ (instancetype)regionWithEN:(NSString *)en cn:(NSString *)cn cities:(NSArray<TZCity *> *)cities;
@end

@interface TimezoneData : NSObject
+ (NSArray<TZRegion *> *)regions;
+ (TZCity *)findCityByTZ:(NSString *)tz;
@end
