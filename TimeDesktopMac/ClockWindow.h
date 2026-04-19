#import <Cocoa/Cocoa.h>

typedef NS_ENUM(NSInteger, DockEdge) {
    DockEdgeTop = 0,
    DockEdgeBottom = 1,
    DockEdgeLeft = 2,
    DockEdgeRight = 3,
};

typedef NS_ENUM(NSInteger, DockPhase) {
    DockPhaseNormal = 0,
    DockPhaseCollapsed,
    DockPhaseExpanding,
    DockPhaseHidden,
};

@interface ZoneEntry : NSObject <NSCoding>
@property (nonatomic, copy) NSString *label;
@property (nonatomic, copy) NSString *tz;
+ (instancetype)entryWithLabel:(NSString *)label tz:(NSString *)tz;
- (NSDictionary *)toDictionary;
+ (instancetype)fromDictionary:(NSDictionary *)d;
@end

@interface AppState : NSObject
@property (nonatomic, strong) NSMutableArray<ZoneEntry *> *zones;
@property (nonatomic) CGFloat fontSize;
@property (nonatomic) BOOL showSeconds;
@property (nonatomic) BOOL dark;
@property (nonatomic) CGFloat opacity;
@property (nonatomic) CGFloat winX;
@property (nonatomic) CGFloat winY;
@property (nonatomic, copy) NSString *lang;
@property (nonatomic) BOOL dockMode;
@property (nonatomic) DockEdge dockEdge;
@property (nonatomic) CGFloat dockAlong;
@property (nonatomic) BOOL pinned;
@property (nonatomic, strong) NSColor *dockColor;
@property (nonatomic) BOOL hasDockColor;
@property (nonatomic) CGFloat stripOpacity;

+ (instancetype)defaultState;
- (void)save;
+ (instancetype)load;
- (BOOL)isEN;
- (NSString *)tr:(NSString *)cn en:(NSString *)en;
@end

@class ClockContentView;

@interface ClockWindow : NSPanel
@property (nonatomic, strong) AppState *state;
@property (nonatomic, strong) ClockContentView *clockView;
@property (nonatomic, strong) NSStatusItem *statusItem;
@property (nonatomic, strong) NSTimer *refreshTimer;
@property (nonatomic) DockPhase phase;
@property (nonatomic) BOOL isHidden;
@property (nonatomic, strong) id globalMonitor;
@property (nonatomic, strong) id localMonitor;
@property (nonatomic, strong) NSTimer *collapseTimer;
@property (nonatomic, strong) NSTimer *edgePollTimer;

- (instancetype)initWithState:(AppState *)st;
- (void)refreshDisplay;
- (void)applyDockLayout;
- (void)showContextMenu:(NSEvent *)event;
- (void)setupStatusItem;
- (void)registerHotkey;
- (void)unregisterHotkey;
@end

@interface ClockContentView : NSView
@property (nonatomic, weak) ClockWindow *clockWindow;
@property (nonatomic, strong) NSTrackingArea *trackingArea;
@end
