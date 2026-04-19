#import "ClockWindow.h"
#import "TimezoneData.h"
#import "NetTimeSync.h"
#import <Carbon/Carbon.h>

static const NSInteger kMaxZones = 10;
static const CGFloat kPadX = 14.0;
static const CGFloat kPadY = 10.0;
static const CGFloat kGapX = 18.0;
static const CGFloat kGapY = 6.0;
static const CGFloat kStripThick = 6.0;
static const CGFloat kEdgeExitThreshold = 40.0;
static const NSTimeInterval kCollapseGraceMS = 0.6;
static const CGFloat kCornerRadius = 8.0;

static EventHotKeyRef sHotkeyRef = NULL;

#pragma mark - ZoneEntry

@implementation ZoneEntry

+ (instancetype)entryWithLabel:(NSString *)label tz:(NSString *)tz {
    ZoneEntry *e = [[ZoneEntry alloc] init];
    e.label = label;
    e.tz = tz;
    return e;
}

- (NSDictionary *)toDictionary {
    return @{@"label": self.label ?: @"", @"tz": self.tz ?: @""};
}

+ (instancetype)fromDictionary:(NSDictionary *)d {
    NSString *label = d[@"label"];
    NSString *tz = d[@"tz"];
    if (!label || ![label isKindOfClass:[NSString class]]) label = @"";
    if (!tz || ![tz isKindOfClass:[NSString class]]) tz = @"Local";
    return [self entryWithLabel:label tz:tz];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super init];
    if (self) {
        _label = [coder decodeObjectForKey:@"label"];
        _tz = [coder decodeObjectForKey:@"tz"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:_label forKey:@"label"];
    [coder encodeObject:_tz forKey:@"tz"];
}

@end

#pragma mark - AppState

@implementation AppState

+ (instancetype)defaultState {
    AppState *s = [[AppState alloc] init];
    s.zones = [NSMutableArray array];
    s.fontSize = 16;
    s.showSeconds = YES;
    s.dark = YES;
    s.opacity = 235.0 / 255.0;
    s.winX = 200;
    s.winY = 200;
    s.lang = @"cn";
    s.dockMode = NO;
    s.dockEdge = DockEdgeTop;
    s.dockAlong = 200;
    s.pinned = NO;
    s.dockColor = [NSColor colorWithRed:60/255.0 green:110/255.0 blue:200/255.0 alpha:1.0];
    s.hasDockColor = NO;
    s.stripOpacity = 160.0 / 255.0;
    return s;
}

- (BOOL)isEN { return [self.lang isEqualToString:@"en"]; }

- (NSString *)tr:(NSString *)cn en:(NSString *)en {
    return self.isEN ? en : cn;
}

- (NSString *)cityLabel:(TZCity *)c {
    return self.isEN ? c.en : c.cn;
}

- (NSString *)regionLabel:(TZRegion *)r {
    return self.isEN ? r.en : r.cn;
}

- (void)refreshLabels {
    for (ZoneEntry *z in self.zones) {
        if ([z.tz isEqualToString:@"Local"]) {
            z.label = [AppState offsetLabelString];
            continue;
        }
        TZCity *c = [TimezoneData findCityByTZ:z.tz];
        if (c) {
            z.label = [self cityLabel:c];
        }
    }
}

+ (NSString *)offsetLabelString {
    NSTimeZone *local = [NSTimeZone localTimeZone];
    NSInteger off = local.secondsFromGMT;
    NSString *sign = off >= 0 ? @"+" : @"-";
    if (off < 0) off = -off;
    NSInteger h = off / 3600;
    NSInteger m = (off % 3600) / 60;
    if (m == 0) {
        return [NSString stringWithFormat:@"UTC%@%ld", sign, (long)h];
    }
    return [NSString stringWithFormat:@"UTC%@%ld:%02ld", sign, (long)h, (long)m];
}

+ (ZoneEntry *)localEntry:(AppState *)st {
    NSString *iana = [NSTimeZone localTimeZone].name;
    if (iana) {
        TZCity *c = [TimezoneData findCityByTZ:iana];
        if (c) {
            return [ZoneEntry entryWithLabel:(st.isEN ? c.en : c.cn) tz:iana];
        }
        return [ZoneEntry entryWithLabel:iana tz:iana];
    }
    return [ZoneEntry entryWithLabel:[self offsetLabelString] tz:@"Local"];
}

- (NSDictionary *)toDictionary {
    NSMutableArray *zArr = [NSMutableArray array];
    for (ZoneEntry *z in self.zones) {
        [zArr addObject:[z toDictionary]];
    }
    CGFloat r = 60/255.0, g = 110/255.0, b = 200/255.0, a = 1.0;
    NSColor *dc = [self.dockColor colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    if (dc) {
        [dc getRed:&r green:&g blue:&b alpha:&a];
    }
    return @{
        @"zones": zArr,
        @"font_size": @(self.fontSize),
        @"show_seconds": @(self.showSeconds),
        @"dark": @(self.dark),
        @"opacity": @(self.opacity),
        @"x": @(self.winX),
        @"y": @(self.winY),
        @"lang": self.lang ?: @"cn",
        @"dock_mode": @(self.dockMode),
        @"dock_edge": @(self.dockEdge),
        @"dock_along": @(self.dockAlong),
        @"pinned": @(self.pinned),
        @"dock_color_r": @(r),
        @"dock_color_g": @(g),
        @"dock_color_b": @(b),
        @"has_dock_color": @(self.hasDockColor),
        @"strip_opacity": @(self.stripOpacity),
    };
}

- (void)save {
    NSDictionary *d = [self toDictionary];
    [[NSUserDefaults standardUserDefaults] setObject:d forKey:@"DesktopTimeState"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

+ (instancetype)load {
    NSDictionary *d = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"DesktopTimeState"];
    AppState *s = [AppState defaultState];
    if (!d) {
        s.zones = [NSMutableArray arrayWithObject:[AppState localEntry:s]];
        return s;
    }

    NSArray *zArr = d[@"zones"];
    if ([zArr isKindOfClass:[NSArray class]] && zArr.count > 0) {
        NSMutableArray *zones = [NSMutableArray array];
        for (NSDictionary *zd in zArr) {
            if ([zd isKindOfClass:[NSDictionary class]]) {
                [zones addObject:[ZoneEntry fromDictionary:zd]];
            }
        }
        s.zones = zones;
    }

    if (d[@"font_size"]) s.fontSize = [d[@"font_size"] doubleValue];
    if (d[@"show_seconds"]) s.showSeconds = [d[@"show_seconds"] boolValue];
    if (d[@"dark"]) s.dark = [d[@"dark"] boolValue];
    if (d[@"opacity"]) s.opacity = [d[@"opacity"] doubleValue];
    if (d[@"x"]) s.winX = [d[@"x"] doubleValue];
    if (d[@"y"]) s.winY = [d[@"y"] doubleValue];
    if (d[@"lang"]) s.lang = d[@"lang"];
    if (d[@"dock_mode"]) s.dockMode = [d[@"dock_mode"] boolValue];
    if (d[@"dock_edge"]) s.dockEdge = (DockEdge)[d[@"dock_edge"] integerValue];
    if (d[@"dock_along"]) s.dockAlong = [d[@"dock_along"] doubleValue];
    if (d[@"pinned"]) s.pinned = [d[@"pinned"] boolValue];
    if (d[@"has_dock_color"]) s.hasDockColor = [d[@"has_dock_color"] boolValue];
    if (d[@"strip_opacity"]) s.stripOpacity = [d[@"strip_opacity"] doubleValue];

    if (d[@"dock_color_r"]) {
        CGFloat cr = [d[@"dock_color_r"] doubleValue];
        CGFloat cg = [d[@"dock_color_g"] doubleValue];
        CGFloat cb = [d[@"dock_color_b"] doubleValue];
        s.dockColor = [NSColor colorWithRed:cr green:cg blue:cb alpha:1.0];
    }

    if (![s.lang isEqualToString:@"en"] && ![s.lang isEqualToString:@"cn"]) {
        s.lang = @"cn";
    }
    if (s.fontSize <= 0) s.fontSize = 16;
    if (s.opacity < 50.0/255.0 || s.opacity > 1.0) s.opacity = 235.0/255.0;
    if (s.stripOpacity < 50.0/255.0 || s.stripOpacity > 1.0) s.stripOpacity = 160.0/255.0;
    if (s.dockEdge < DockEdgeTop || s.dockEdge > DockEdgeRight) s.dockEdge = DockEdgeTop;

    if (!s.hasDockColor) {
        s.dockColor = [NSColor colorWithRed:60/255.0 green:110/255.0 blue:200/255.0 alpha:1.0];
    }

    if (s.zones.count == 0) {
        s.zones = [NSMutableArray arrayWithObject:[AppState localEntry:s]];
    }

    [s refreshLabels];
    return s;
}

@end

#pragma mark - ClockContentView

@implementation ClockContentView

- (BOOL)isFlipped { return YES; }

- (NSView *)hitTest:(NSPoint)point {
    ClockWindow *cw = self.clockWindow;
    if (cw && !cw.state.dockMode) {
        NSPoint local = [self convertPoint:point fromView:self.superview];
        NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:self.bounds
                                                             xRadius:kCornerRadius
                                                             yRadius:kCornerRadius];
        if (![path containsPoint:local]) return nil;
    }
    return [super hitTest:point];
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (self.trackingArea) {
        [self removeTrackingArea:self.trackingArea];
    }
    self.trackingArea = [[NSTrackingArea alloc]
        initWithRect:self.bounds
             options:(NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect)
               owner:self
            userInfo:nil];
    [self addTrackingArea:self.trackingArea];
}

- (void)drawRect:(NSRect)dirtyRect {
    ClockWindow *cw = self.clockWindow;
    if (!cw) return;
    AppState *st = cw.state;

    NSRect bounds = self.bounds;

    if (st.dockMode && cw.phase == DockPhaseCollapsed) {
        [st.dockColor setFill];
        NSRectFill(bounds);
        return;
    }

    NSColor *bgColor;
    if (st.dark) {
        bgColor = [NSColor colorWithRed:22/255.0 green:24/255.0 blue:30/255.0 alpha:1.0];
    } else {
        bgColor = [NSColor colorWithRed:248/255.0 green:248/255.0 blue:250/255.0 alpha:1.0];
    }

    if (st.dockMode) {
        [bgColor setFill];
        NSRectFill(bounds);
    } else {
        NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:bounds
                                                             xRadius:kCornerRadius
                                                             yRadius:kCornerRadius];
        [bgColor setFill];
        [path fill];
    }

    NSColor *textCol;
    if (st.dark) {
        textCol = [NSColor colorWithRed:232/255.0 green:232/255.0 blue:238/255.0 alpha:1.0];
    } else {
        textCol = [NSColor colorWithRed:28/255.0 green:28/255.0 blue:32/255.0 alpha:1.0];
    }

    NSFont *font = [NSFont fontWithName:@"PingFang SC" size:st.fontSize];
    if (!font) font = [NSFont systemFontOfSize:st.fontSize];

    NSDictionary *attrs = @{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName: textCol,
    };

    CGFloat labelW = 0, timeW = 0, lineH = 0;
    NSInteger n = st.zones.count;
    NSMutableArray<NSString *> *timeStrings = [NSMutableArray arrayWithCapacity:n];
    for (ZoneEntry *z in st.zones) {
        NSString *label = z.label ?: @"";
        NSSize ls = [label sizeWithAttributes:attrs];
        NSString *ts = [self formatTime:z state:st];
        [timeStrings addObject:ts];
        NSSize tsz = [ts sizeWithAttributes:attrs];
        if (ls.width > labelW) labelW = ls.width;
        if (tsz.width > timeW) timeW = tsz.width;
        CGFloat h = MAX(ls.height, tsz.height);
        if (h > lineH) lineH = h;
    }
    lineH += kGapY;

    CGFloat timeX = kPadX + labelW + kGapX;
    CGFloat y = kPadY;
    for (NSInteger i = 0; i < n; i++) {
        ZoneEntry *z = st.zones[i];
        NSString *label = z.label ?: @"";
        [label drawAtPoint:NSMakePoint(kPadX, y) withAttributes:attrs];
        [timeStrings[i] drawAtPoint:NSMakePoint(timeX, y) withAttributes:attrs];
        y += lineH;
    }
}

- (NSString *)formatTime:(ZoneEntry *)z state:(AppState *)st {
    static NSDateFormatter *sFmtSec;
    static NSDateFormatter *sFmtNoSec;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sFmtSec = [[NSDateFormatter alloc] init];
        sFmtSec.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
        sFmtSec.dateFormat = @"HH:mm:ss";
        sFmtNoSec = [[NSDateFormatter alloc] init];
        sFmtNoSec.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
        sFmtNoSec.dateFormat = @"HH:mm";
    });
    NSDateFormatter *fmt = st.showSeconds ? sFmtSec : sFmtNoSec;
    NSDate *now = [[NetTimeSync shared] correctedNow];

    if (z.tz && ![z.tz isEqualToString:@"Local"]) {
        NSTimeZone *tz = [NSTimeZone timeZoneWithName:z.tz];
        if (tz) fmt.timeZone = tz;
        else fmt.timeZone = [NSTimeZone localTimeZone];
    } else {
        fmt.timeZone = [NSTimeZone localTimeZone];
    }
    return [fmt stringFromDate:now];
}

- (void)mouseDown:(NSEvent *)event {
    ClockWindow *cw = self.clockWindow;
    if (event.clickCount == 1) {
        [cw performSelector:@selector(startDrag:) withObject:event];
    }
}

- (void)rightMouseUp:(NSEvent *)event {
    [self.clockWindow showContextMenu:event];
}

- (void)mouseEntered:(NSEvent *)event {
    ClockWindow *cw = self.clockWindow;
    if (!cw) return;
    if (cw.state.dockMode && !cw.isHidden) {
        [cw.collapseTimer invalidate];
        cw.collapseTimer = nil;
        if (cw.phase == DockPhaseCollapsed) {
            cw.phase = DockPhaseExpanding;
            [cw applyDockLayout];
        }
    }
}

- (void)mouseExited:(NSEvent *)event {
    ClockWindow *cw = self.clockWindow;
    if (!cw) return;
    if (cw.state.dockMode && !cw.state.pinned && !cw.isHidden && cw.phase == DockPhaseExpanding) {
        NSPoint mouseLoc = [NSEvent mouseLocation];
        NSRect frame = cw.frame;
        NSRect inflated = NSInsetRect(frame, -8, -8);
        if (NSPointInRect(mouseLoc, inflated)) return;
        [cw.collapseTimer invalidate];
        cw.collapseTimer = [NSTimer scheduledTimerWithTimeInterval:kCollapseGraceMS
                                                            target:cw
                                                          selector:@selector(collapseTimerFired)
                                                          userInfo:nil
                                                           repeats:NO];
    }
}

@end

#pragma mark - ClockWindow

@implementation ClockWindow {
    NSPoint _dragOrigin;
    NSPoint _windowOrigin;
}

- (instancetype)initWithState:(AppState *)st {
    NSSize sz = [ClockWindow desiredSizeForState:st];
    NSRect frame = NSMakeRect(st.winX, st.winY, sz.width, sz.height);

    self = [super initWithContentRect:frame
                            styleMask:(NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel)
                              backing:NSBackingStoreBuffered
                                defer:NO];
    if (self) {
        _state = st;
        _phase = DockPhaseNormal;
        _isHidden = NO;

        self.level = NSFloatingWindowLevel;
        self.hidesOnDeactivate = NO;
        self.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces |
                                  NSWindowCollectionBehaviorStationary |
                                  NSWindowCollectionBehaviorFullScreenAuxiliary;
        self.hasShadow = YES;
        self.opaque = NO;
        self.backgroundColor = [NSColor clearColor];
        self.alphaValue = st.opacity;
        self.movableByWindowBackground = NO;

        ClockContentView *cv = [[ClockContentView alloc] initWithFrame:NSMakeRect(0, 0, sz.width, sz.height)];
        cv.clockWindow = self;
        self.clockView = cv;
        self.contentView = cv;

        if (st.dockMode) {
            _phase = DockPhaseCollapsed;
        }
    }
    return self;
}

- (BOOL)canBecomeKeyWindow { return YES; }
- (BOOL)canBecomeMainWindow { return NO; }
- (BOOL)isOpaque { return NO; }

+ (NSSize)desiredSizeForState:(AppState *)st {
    NSFont *font = [NSFont fontWithName:@"PingFang SC" size:st.fontSize];
    if (!font) font = [NSFont systemFontOfSize:st.fontSize];
    NSDictionary *attrs = @{NSFontAttributeName: font};

    CGFloat labelW = 0, timeW = 0, lineH = 0;
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = st.showSeconds ? @"HH:mm:ss" : @"HH:mm";

    NSTimeZone *localTZ = [NSTimeZone localTimeZone];
    for (ZoneEntry *z in st.zones) {
        NSString *label = z.label ?: @"";
        NSSize ls = [label sizeWithAttributes:attrs];
        if (z.tz && ![z.tz isEqualToString:@"Local"]) {
            NSTimeZone *tz = [NSTimeZone timeZoneWithName:z.tz];
            fmt.timeZone = tz ?: localTZ;
        } else {
            fmt.timeZone = localTZ;
        }
        NSString *sampleTime = [fmt stringFromDate:[NSDate date]];
        NSSize ts = [sampleTime sizeWithAttributes:attrs];
        if (ls.width > labelW) labelW = ls.width;
        if (ts.width > timeW) timeW = ts.width;
        CGFloat h = MAX(ls.height, ts.height);
        if (h > lineH) lineH = h;
    }
    lineH += kGapY;

    CGFloat w = kPadX * 2 + labelW + kGapX + timeW;
    NSInteger n = st.zones.count;
    if (n < 1) n = 1;
    CGFloat h = kPadY * 2 + n * lineH;
    if (w < 96) w = 96;
    return NSMakeSize(ceil(w), ceil(h));
}

- (void)refreshDisplay {
    [self.clockView setNeedsDisplay:YES];
}

#pragma mark - Drag

- (void)startDrag:(NSEvent *)event {
    _dragOrigin = [NSEvent mouseLocation];
    _windowOrigin = self.frame.origin;

    while (YES) {
        NSEvent *ev = [self nextEventMatchingMask:(NSEventMaskLeftMouseDragged | NSEventMaskLeftMouseUp)];
        if (ev.type == NSEventTypeLeftMouseUp) {
            [self dragEnded];
            break;
        }
        NSPoint cur = [NSEvent mouseLocation];
        CGFloat dx = cur.x - _dragOrigin.x;
        CGFloat dy = cur.y - _dragOrigin.y;
        NSPoint newOrigin = NSMakePoint(_windowOrigin.x + dx, _windowOrigin.y + dy);
        [self setFrameOrigin:newOrigin];
    }
}

- (void)dragEnded {
    if (self.state.dockMode) {
        NSRect rc = self.frame;
        NSRect work = [self workArea];
        CGFloat dist = [self perpDistanceToEdge:rc work:work edge:self.state.dockEdge];
        if (dist > kEdgeExitThreshold) {
            self.state.dockMode = NO;
            self.state.pinned = NO;
            self.isHidden = NO;
            self.state.winX = rc.origin.x;
            self.state.winY = rc.origin.y;
            self.phase = DockPhaseNormal;
            [self applyDockLayout];
        } else {
            self.state.dockAlong = [self alongCoord:rc edge:self.state.dockEdge];
            [self applyDockLayout];
        }
        [self.state save];
    } else {
        NSRect rc = self.frame;
        self.state.winX = rc.origin.x;
        self.state.winY = rc.origin.y;
        [self.state save];
    }
}

#pragma mark - Dock Layout

- (NSRect)workArea {
    NSScreen *screen = self.screen ?: [NSScreen mainScreen];
    return screen.visibleFrame;
}

- (BOOL)edgeIsHorizontal:(DockEdge)edge {
    return edge == DockEdgeTop || edge == DockEdgeBottom;
}

static CGFloat clampVal(CGFloat v, CGFloat lo, CGFloat hi) {
    if (v < lo) return lo;
    if (v > hi) return hi;
    return v;
}

- (NSRect)dockedRect:(NSRect)work fw:(CGFloat)fw fh:(CGFloat)fh thick:(CGFloat)thick {
    CGFloat along = self.state.dockAlong;
    switch (self.state.dockEdge) {
        case DockEdgeTop: {
            along = clampVal(along, NSMinX(work), NSMaxX(work) - fw);
            return NSMakeRect(along, NSMaxY(work) - thick, fw, thick);
        }
        case DockEdgeBottom: {
            along = clampVal(along, NSMinX(work), NSMaxX(work) - fw);
            return NSMakeRect(along, NSMinY(work), fw, thick);
        }
        case DockEdgeLeft: {
            along = clampVal(along, NSMinY(work), NSMaxY(work) - fh);
            return NSMakeRect(NSMinX(work), along, thick, fh);
        }
        case DockEdgeRight: {
            along = clampVal(along, NSMinY(work), NSMaxY(work) - fh);
            return NSMakeRect(NSMaxX(work) - thick, along, thick, fh);
        }
    }
    return NSMakeRect(along, NSMaxY(work) - thick, fw, thick);
}

- (NSRect)stripRect:(NSRect)work fw:(CGFloat)fw fh:(CGFloat)fh {
    return [self dockedRect:work fw:fw fh:fh thick:kStripThick];
}

- (NSRect)expandedRect:(NSRect)work fw:(CGFloat)fw fh:(CGFloat)fh {
    CGFloat thick = fh;
    if (![self edgeIsHorizontal:self.state.dockEdge]) {
        thick = fw;
    }
    return [self dockedRect:work fw:fw fh:fh thick:thick];
}

- (CGFloat)perpDistanceToEdge:(NSRect)rc work:(NSRect)work edge:(DockEdge)edge {
    CGFloat d = 0;
    switch (edge) {
        case DockEdgeTop: d = NSMaxY(work) - NSMaxY(rc); break;
        case DockEdgeBottom: d = NSMinY(rc) - NSMinY(work); break;
        case DockEdgeLeft: d = NSMinX(rc) - NSMinX(work); break;
        case DockEdgeRight: d = NSMaxX(work) - NSMaxX(rc); break;
    }
    return fabs(d);
}

- (CGFloat)alongCoord:(NSRect)rc edge:(DockEdge)edge {
    if ([self edgeIsHorizontal:edge]) return rc.origin.x;
    return rc.origin.y;
}

- (CGFloat)centerAlong:(DockEdge)edge {
    NSRect work = [self workArea];
    NSSize sz = [ClockWindow desiredSizeForState:self.state];
    if ([self edgeIsHorizontal:edge]) {
        return NSMinX(work) + (NSWidth(work) - sz.width) / 2;
    }
    return NSMinY(work) + (NSHeight(work) - sz.height) / 2;
}

- (void)applyDockLayout {
    NSSize sz = [ClockWindow desiredSizeForState:self.state];
    CGFloat fw = sz.width, fh = sz.height;

    if (self.isHidden) {
        self.phase = DockPhaseHidden;
        [self orderOut:nil];
        [self stopEdgePoll];
        return;
    }

    if (!self.state.dockMode) {
        self.phase = DockPhaseNormal;
        self.level = NSFloatingWindowLevel;
        [self setFrame:NSMakeRect(self.state.winX, self.state.winY, fw, fh) display:YES];
        self.alphaValue = self.state.opacity;
        [self orderFront:nil];
        [self.clockView setNeedsDisplay:YES];
        [self stopEdgePoll];
        return;
    }

    self.level = NSStatusWindowLevel;

    NSRect work = [self workArea];
    NSRect r;
    if (self.state.pinned || self.phase == DockPhaseExpanding) {
        self.phase = DockPhaseExpanding;
        r = [self expandedRect:work fw:fw fh:fh];
        [self stopEdgePoll];
    } else {
        self.phase = DockPhaseCollapsed;
        r = [self stripRect:work fw:fw fh:fh];
        [self startEdgePoll];
    }

    CGFloat op = self.state.opacity;
    if (self.phase == DockPhaseCollapsed) {
        op = self.state.stripOpacity;
    }

    [self setFrame:r display:YES];
    self.alphaValue = op;
    [self orderFront:nil];
    [self.clockView setNeedsDisplay:YES];
}

- (void)enterDockMode {
    NSRect rc = self.frame;
    NSRect work = [self workArea];
    CGFloat cx = NSMidX(rc);
    CGFloat cy = NSMidY(rc);

    CGFloat dTop = NSMaxY(work) - cy;
    CGFloat dBottom = cy - NSMinY(work);
    CGFloat dLeft = cx - NSMinX(work);
    CGFloat dRight = NSMaxX(work) - cx;

    DockEdge edge = DockEdgeTop;
    CGFloat best = dTop;
    if (dBottom < best) { edge = DockEdgeBottom; best = dBottom; }
    if (dLeft < best) { edge = DockEdgeLeft; best = dLeft; }
    if (dRight < best) { edge = DockEdgeRight; best = dRight; }
    self.state.dockEdge = edge;

    NSSize sz = [ClockWindow desiredSizeForState:self.state];
    if ([self edgeIsHorizontal:edge]) {
        self.state.dockAlong = clampVal(rc.origin.x, NSMinX(work), NSMaxX(work) - sz.width);
    } else {
        self.state.dockAlong = clampVal(rc.origin.y, NSMinY(work), NSMaxY(work) - sz.height);
    }

    self.phase = DockPhaseCollapsed;
}

- (void)collapseTimerFired {
    self.collapseTimer = nil;
    if (self.state.dockMode && !self.state.pinned && !self.isHidden && self.phase == DockPhaseExpanding) {
        NSPoint mouseLoc = [NSEvent mouseLocation];
        NSRect frame = self.frame;
        NSRect inflated = NSInsetRect(frame, -8, -8);
        if (NSPointInRect(mouseLoc, inflated)) return;
        self.phase = DockPhaseCollapsed;
        [self applyDockLayout];
    }
}

#pragma mark - Edge Poll

- (void)startEdgePoll {
    if (self.edgePollTimer) return;
    self.edgePollTimer = [NSTimer scheduledTimerWithTimeInterval:0.1
                                                         target:self
                                                       selector:@selector(edgePollTick)
                                                       userInfo:nil
                                                        repeats:YES];
    self.edgePollTimer.tolerance = 0.05;
}

- (void)stopEdgePoll {
    [self.edgePollTimer invalidate];
    self.edgePollTimer = nil;
}

- (void)edgePollTick {
    if (!self.state.dockMode || self.isHidden || self.phase != DockPhaseCollapsed) {
        [self stopEdgePoll];
        return;
    }
    NSPoint mouseLoc = [NSEvent mouseLocation];
    NSRect frame = self.frame;
    NSRect hitZone = NSInsetRect(frame, -10, -10);
    if (NSPointInRect(mouseLoc, hitZone)) {
        [self stopEdgePoll];
        self.phase = DockPhaseExpanding;
        [self applyDockLayout];
    }
}

#pragma mark - Context Menu

- (void)showContextMenu:(NSEvent *)event {
    NSMenu *menu = [self buildMenu];
    [NSMenu popUpContextMenu:menu withEvent:event forView:self.clockView];
}

- (NSMenu *)buildMenu {
    AppState *st = self.state;
    NSMenu *root = [[NSMenu alloc] init];

    // --- Add zone ---
    NSMenuItem *addItem = [[NSMenuItem alloc] initWithTitle:[st tr:@"添加时区" en:@"Add Zone"]
                                                    action:nil
                                             keyEquivalent:@""];
    BOOL full = st.zones.count >= kMaxZones;
    if (full) {
        addItem.title = [st tr:@"添加时区（已达上限 10）" en:@"Add Zone (max 10 reached)"];
        addItem.enabled = NO;
    }
    NSMenu *addMenu = [[NSMenu alloc] init];
    for (TZRegion *reg in [TimezoneData regions]) {
        NSMenuItem *regItem = [[NSMenuItem alloc] initWithTitle:[st regionLabel:reg]
                                                        action:nil
                                                 keyEquivalent:@""];
        NSMenu *citySub = [[NSMenu alloc] init];
        for (TZCity *city in reg.cities) {
            NSString *label = [st cityLabel:city];
            NSMenuItem *cityItem = [[NSMenuItem alloc] initWithTitle:label
                                                             action:@selector(addZoneAction:)
                                                      keyEquivalent:@""];
            cityItem.target = self;
            cityItem.representedObject = city;
            BOOL exists = NO;
            for (ZoneEntry *z in st.zones) {
                if ([z.tz isEqualToString:city.tz]) { exists = YES; break; }
            }
            if (exists || full) cityItem.enabled = NO;
            [citySub addItem:cityItem];
        }
        regItem.submenu = citySub;
        [addMenu addItem:regItem];
    }
    addItem.submenu = addMenu;
    [root addItem:addItem];

    // --- Remove zone ---
    NSMenuItem *delItem = [[NSMenuItem alloc] initWithTitle:[st tr:@"删除时区" en:@"Remove Zone"]
                                                    action:nil
                                             keyEquivalent:@""];
    NSMenu *delMenu = [[NSMenu alloc] init];
    for (NSInteger i = 0; i < (NSInteger)st.zones.count; i++) {
        ZoneEntry *z = st.zones[i];
        NSString *title = [NSString stringWithFormat:@"%@   (%@)", z.label, z.tz];
        NSMenuItem *di = [[NSMenuItem alloc] initWithTitle:title
                                                   action:@selector(removeZoneAction:)
                                            keyEquivalent:@""];
        di.target = self;
        di.tag = i;
        if (st.zones.count <= 1) di.enabled = NO;
        [delMenu addItem:di];
    }
    delItem.submenu = delMenu;
    [root addItem:delItem];

    [root addItem:[NSMenuItem separatorItem]];

    // --- Show seconds ---
    NSMenuItem *secItem = [[NSMenuItem alloc] initWithTitle:[st tr:@"显示秒" en:@"Show seconds"]
                                                    action:@selector(toggleSeconds:)
                                             keyEquivalent:@""];
    secItem.target = self;
    secItem.state = st.showSeconds ? NSControlStateValueOn : NSControlStateValueOff;
    [root addItem:secItem];

    // --- Font size ---
    NSMenuItem *sizeItem = [[NSMenuItem alloc] initWithTitle:[st tr:@"字号" en:@"Font size"]
                                                     action:nil
                                              keyEquivalent:@""];
    NSMenu *sizeSub = [[NSMenu alloc] init];
    struct { NSString *label; CGFloat val; } sizes[] = {
        {@"", 13}, {@"", 16}, {@"", 20}, {@"", 24}
    };
    sizes[0].label = [st tr:@"小 (13)" en:@"Small (13)"];
    sizes[1].label = [st tr:@"中 (16)" en:@"Medium (16)"];
    sizes[2].label = [st tr:@"大 (20)" en:@"Large (20)"];
    sizes[3].label = [st tr:@"特大 (24)" en:@"X-Large (24)"];
    for (int i = 0; i < 4; i++) {
        NSMenuItem *si = [[NSMenuItem alloc] initWithTitle:sizes[i].label
                                                   action:@selector(setFontSize:)
                                            keyEquivalent:@""];
        si.target = self;
        si.tag = (NSInteger)sizes[i].val;
        si.state = (st.fontSize == sizes[i].val) ? NSControlStateValueOn : NSControlStateValueOff;
        [sizeSub addItem:si];
    }
    sizeItem.submenu = sizeSub;
    [root addItem:sizeItem];

    // --- Opacity ---
    NSMenuItem *opItem = [[NSMenuItem alloc] initWithTitle:[st tr:@"透明度" en:@"Opacity"]
                                                   action:nil
                                            keyEquivalent:@""];
    NSMenu *opSub = [[NSMenu alloc] init];
    struct { NSString *label; CGFloat val; } ops[] = {
        {@"100%", 1.0}, {@"90%", 230.0/255.0}, {@"80%", 205.0/255.0},
        {@"70%", 180.0/255.0}, {@"60%", 155.0/255.0}
    };
    for (int i = 0; i < 5; i++) {
        NSMenuItem *oi = [[NSMenuItem alloc] initWithTitle:ops[i].label
                                                   action:@selector(setOpacity:)
                                            keyEquivalent:@""];
        oi.target = self;
        oi.tag = (NSInteger)(ops[i].val * 1000);
        oi.state = (fabs(st.opacity - ops[i].val) < 0.01) ? NSControlStateValueOn : NSControlStateValueOff;
        [opSub addItem:oi];
    }
    opItem.submenu = opSub;
    [root addItem:opItem];

    // --- Theme ---
    NSMenuItem *themeItem = [[NSMenuItem alloc] initWithTitle:[st tr:@"主题" en:@"Theme"]
                                                      action:nil
                                               keyEquivalent:@""];
    NSMenu *themeSub = [[NSMenu alloc] init];
    NSMenuItem *darkItem = [[NSMenuItem alloc] initWithTitle:[st tr:@"深色" en:@"Dark"]
                                                     action:@selector(setThemeDark:)
                                              keyEquivalent:@""];
    darkItem.target = self;
    darkItem.state = st.dark ? NSControlStateValueOn : NSControlStateValueOff;
    [themeSub addItem:darkItem];
    NSMenuItem *lightItem = [[NSMenuItem alloc] initWithTitle:[st tr:@"浅色" en:@"Light"]
                                                      action:@selector(setThemeLight:)
                                               keyEquivalent:@""];
    lightItem.target = self;
    lightItem.state = st.dark ? NSControlStateValueOff : NSControlStateValueOn;
    [themeSub addItem:lightItem];
    themeItem.submenu = themeSub;
    [root addItem:themeItem];

    // --- Language ---
    NSMenuItem *langItem = [[NSMenuItem alloc] initWithTitle:[st tr:@"语言" en:@"Language"]
                                                     action:nil
                                              keyEquivalent:@""];
    NSMenu *langSub = [[NSMenu alloc] init];
    NSMenuItem *cnItem = [[NSMenuItem alloc] initWithTitle:@"中文"
                                                   action:@selector(setLangCN:)
                                            keyEquivalent:@""];
    cnItem.target = self;
    cnItem.state = [st.lang isEqualToString:@"cn"] ? NSControlStateValueOn : NSControlStateValueOff;
    [langSub addItem:cnItem];
    NSMenuItem *enItem = [[NSMenuItem alloc] initWithTitle:@"English"
                                                   action:@selector(setLangEN:)
                                            keyEquivalent:@""];
    enItem.target = self;
    enItem.state = [st.lang isEqualToString:@"en"] ? NSControlStateValueOn : NSControlStateValueOff;
    [langSub addItem:enItem];
    langItem.submenu = langSub;
    [root addItem:langItem];

    // --- Dock ---
    NSMenuItem *dockItem = [[NSMenuItem alloc] initWithTitle:[st tr:@"停靠" en:@"Dock"]
                                                     action:nil
                                              keyEquivalent:@""];
    NSMenu *dockSub = [[NSMenu alloc] init];

    NSMenuItem *dockToggle = [[NSMenuItem alloc] initWithTitle:[st tr:@"边缘停靠" en:@"Edge dock"]
                                                       action:@selector(toggleDockMode:)
                                                keyEquivalent:@""];
    dockToggle.target = self;
    dockToggle.state = st.dockMode ? NSControlStateValueOn : NSControlStateValueOff;
    [dockSub addItem:dockToggle];

    [dockSub addItem:[NSMenuItem separatorItem]];

    struct { NSString *cn; NSString *en; DockEdge edge; } edges[] = {
        {@"吸附到上边", @"Dock top", DockEdgeTop},
        {@"吸附到下边", @"Dock bottom", DockEdgeBottom},
        {@"吸附到左边", @"Dock left", DockEdgeLeft},
        {@"吸附到右边", @"Dock right", DockEdgeRight},
    };
    for (int i = 0; i < 4; i++) {
        NSMenuItem *ei = [[NSMenuItem alloc] initWithTitle:[st tr:edges[i].cn en:edges[i].en]
                                                   action:@selector(setDockEdge:)
                                            keyEquivalent:@""];
        ei.target = self;
        ei.tag = edges[i].edge;
        ei.state = (st.dockEdge == edges[i].edge) ? NSControlStateValueOn : NSControlStateValueOff;
        if (!st.dockMode) ei.enabled = NO;
        [dockSub addItem:ei];
    }

    [dockSub addItem:[NSMenuItem separatorItem]];

    NSMenuItem *pinItem = [[NSMenuItem alloc] initWithTitle:[st tr:@"固定展开" en:@"Pin expanded"]
                                                    action:@selector(togglePinned:)
                                             keyEquivalent:@""];
    pinItem.target = self;
    pinItem.state = st.pinned ? NSControlStateValueOn : NSControlStateValueOff;
    if (!st.dockMode) pinItem.enabled = NO;
    [dockSub addItem:pinItem];

    NSMenuItem *hideItem = [[NSMenuItem alloc] initWithTitle:[st tr:@"隐藏 (⌘⌥T)" en:@"Hide (⌘⌥T)"]
                                                     action:@selector(toggleHidden:)
                                              keyEquivalent:@""];
    hideItem.target = self;
    hideItem.state = self.isHidden ? NSControlStateValueOn : NSControlStateValueOff;
    [dockSub addItem:hideItem];

    [dockSub addItem:[NSMenuItem separatorItem]];

    // --- Dock color ---
    NSMenuItem *colorItem = [[NSMenuItem alloc] initWithTitle:[st tr:@"边缘色" en:@"Strip color"]
                                                      action:nil
                                               keyEquivalent:@""];
    NSMenu *colorSub = [[NSMenu alloc] init];
    struct { NSString *cn; NSString *en; CGFloat r; CGFloat g; CGFloat b; } presets[] = {
        {@"蓝", @"Blue", 60, 110, 200},
        {@"紫", @"Purple", 145, 85, 195},
        {@"青", @"Teal", 45, 170, 180},
        {@"绿", @"Green", 80, 170, 95},
        {@"橙", @"Orange", 230, 140, 55},
        {@"粉", @"Pink", 225, 100, 140},
    };
    for (int i = 0; i < 6; i++) {
        NSColor *pc = [NSColor colorWithRed:presets[i].r/255.0 green:presets[i].g/255.0 blue:presets[i].b/255.0 alpha:1.0];
        NSMenuItem *pi = [[NSMenuItem alloc] initWithTitle:[st tr:presets[i].cn en:presets[i].en]
                                                    action:@selector(setDockColorPreset:)
                                             keyEquivalent:@""];
        pi.target = self;
        pi.representedObject = pc;
        if (st.hasDockColor) {
            pi.state = [self colorsEqual:st.dockColor b:pc] ? NSControlStateValueOn : NSControlStateValueOff;
        }
        [colorSub addItem:pi];
    }
    [colorSub addItem:[NSMenuItem separatorItem]];
    NSMenuItem *customColor = [[NSMenuItem alloc] initWithTitle:[st tr:@"自定义…" en:@"Custom…"]
                                                        action:@selector(pickCustomColor:)
                                                 keyEquivalent:@""];
    customColor.target = self;
    [colorSub addItem:customColor];
    colorItem.submenu = colorSub;
    [dockSub addItem:colorItem];

    // --- Strip opacity ---
    NSMenuItem *stripOpItem = [[NSMenuItem alloc] initWithTitle:[st tr:@"小条透明度" en:@"Strip opacity"]
                                                        action:nil
                                                 keyEquivalent:@""];
    NSMenu *stripOpSub = [[NSMenu alloc] init];
    struct { NSString *label; CGFloat val; } stripOps[] = {
        {@"100%", 1.0}, {@"80%", 204.0/255.0}, {@"60%", 153.0/255.0},
        {@"40%", 102.0/255.0}, {@"25%", 64.0/255.0}
    };
    for (int i = 0; i < 5; i++) {
        NSMenuItem *soi = [[NSMenuItem alloc] initWithTitle:stripOps[i].label
                                                    action:@selector(setStripOpacity:)
                                             keyEquivalent:@""];
        soi.target = self;
        soi.tag = (NSInteger)(stripOps[i].val * 1000);
        soi.state = (fabs(st.stripOpacity - stripOps[i].val) < 0.01) ? NSControlStateValueOn : NSControlStateValueOff;
        [stripOpSub addItem:soi];
    }
    stripOpItem.submenu = stripOpSub;
    [dockSub addItem:stripOpItem];

    dockItem.submenu = dockSub;
    [root addItem:dockItem];

    [root addItem:[NSMenuItem separatorItem]];

    // --- Reset ---
    NSMenuItem *resetItem = [[NSMenuItem alloc] initWithTitle:[st tr:@"恢复默认" en:@"Reset to defaults"]
                                                      action:@selector(resetDefaults:)
                                               keyEquivalent:@""];
    resetItem.target = self;
    [root addItem:resetItem];

    // --- Quit ---
    NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:[st tr:@"退出" en:@"Quit"]
                                                      action:@selector(quitApp:)
                                               keyEquivalent:@""];
    quitItem.target = self;
    [root addItem:quitItem];

    return root;
}

- (BOOL)colorsEqual:(NSColor *)a b:(NSColor *)b {
    NSColor *ca = [a colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    NSColor *cb = [b colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    return fabs(ca.redComponent - cb.redComponent) < 0.01 &&
           fabs(ca.greenComponent - cb.greenComponent) < 0.01 &&
           fabs(ca.blueComponent - cb.blueComponent) < 0.01;
}

#pragma mark - Menu Actions

- (void)addZoneAction:(NSMenuItem *)sender {
    TZCity *city = sender.representedObject;
    if (self.state.zones.count >= kMaxZones) return;
    for (ZoneEntry *z in self.state.zones) {
        if ([z.tz isEqualToString:city.tz]) return;
    }
    [self.state.zones addObject:[ZoneEntry entryWithLabel:[self.state cityLabel:city] tz:city.tz]];
    [self.state save];
    [self applyDockLayout];
}

- (void)removeZoneAction:(NSMenuItem *)sender {
    NSInteger idx = sender.tag;
    if (idx < 0 || idx >= (NSInteger)self.state.zones.count || self.state.zones.count <= 1) return;
    [self.state.zones removeObjectAtIndex:idx];
    [self.state save];
    [self applyDockLayout];
}

- (void)toggleSeconds:(NSMenuItem *)sender {
    self.state.showSeconds = !self.state.showSeconds;
    [self.state save];
    [self applyDockLayout];
}

- (void)setFontSize:(NSMenuItem *)sender {
    self.state.fontSize = sender.tag;
    [self.state save];
    [self applyDockLayout];
}

- (void)setOpacity:(NSMenuItem *)sender {
    self.state.opacity = sender.tag / 1000.0;
    [self.state save];
    self.alphaValue = self.state.opacity;
}

- (void)setThemeDark:(id)sender {
    self.state.dark = YES;
    [self.state save];
    [self.clockView setNeedsDisplay:YES];
}

- (void)setThemeLight:(id)sender {
    self.state.dark = NO;
    [self.state save];
    [self.clockView setNeedsDisplay:YES];
}

- (void)setLangCN:(id)sender {
    self.state.lang = @"cn";
    [self.state refreshLabels];
    [self.state save];
    [self applyDockLayout];
}

- (void)setLangEN:(id)sender {
    self.state.lang = @"en";
    [self.state refreshLabels];
    [self.state save];
    [self applyDockLayout];
}

- (void)toggleDockMode:(id)sender {
    self.state.dockMode = !self.state.dockMode;
    if (self.state.dockMode) {
        [self enterDockMode];
    } else {
        self.phase = DockPhaseNormal;
    }
    [self.state save];
    [self applyDockLayout];
}

- (void)setDockEdge:(NSMenuItem *)sender {
    self.state.dockEdge = (DockEdge)sender.tag;
    self.state.dockAlong = [self centerAlong:self.state.dockEdge];
    self.phase = DockPhaseCollapsed;
    [self.state save];
    [self applyDockLayout];
}

- (void)togglePinned:(id)sender {
    self.state.pinned = !self.state.pinned;
    [self.state save];
    [self applyDockLayout];
}

- (void)toggleHidden:(id)sender {
    self.isHidden = !self.isHidden;
    [self applyDockLayout];
}

- (void)setDockColorPreset:(NSMenuItem *)sender {
    self.state.dockColor = sender.representedObject;
    self.state.hasDockColor = YES;
    [self.state save];
    [self.clockView setNeedsDisplay:YES];
}

- (void)pickCustomColor:(id)sender {
    NSColorPanel *panel = [NSColorPanel sharedColorPanel];
    panel.color = self.state.dockColor;
    panel.target = self;
    panel.action = @selector(colorPanelChanged:);
    panel.continuous = YES;
    [panel orderFront:nil];
}

- (void)colorPanelChanged:(NSColorPanel *)panel {
    self.state.dockColor = panel.color;
    self.state.hasDockColor = YES;
    [self.state save];
    [self.clockView setNeedsDisplay:YES];
}

- (void)setStripOpacity:(NSMenuItem *)sender {
    self.state.stripOpacity = sender.tag / 1000.0;
    [self.state save];
    if (self.phase == DockPhaseCollapsed) {
        self.alphaValue = self.state.stripOpacity;
    }
}

- (void)resetDefaults:(id)sender {
    NSString *keepLang = self.state.lang;
    AppState *fresh = [AppState defaultState];
    fresh.lang = keepLang;
    fresh.zones = [NSMutableArray arrayWithObject:[AppState localEntry:fresh]];
    [fresh refreshLabels];
    self.state = fresh;
    [self.state save];
    self.isHidden = NO;
    self.phase = DockPhaseNormal;
    [self applyDockLayout];
}

- (void)quitApp:(id)sender {
    if (!self.state.dockMode) {
        NSRect rc = self.frame;
        self.state.winX = rc.origin.x;
        self.state.winY = rc.origin.y;
    }
    [self unregisterHotkey];
    [self.state save];
    [NSApp terminate:nil];
}

#pragma mark - Status Item

- (void)setupStatusItem {
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSSquareStatusItemLength];
    NSImage *icon = [self drawStatusIcon];
    self.statusItem.button.image = icon;
    self.statusItem.button.target = self;
    self.statusItem.button.action = @selector(statusItemClicked:);
    [self.statusItem.button sendActionOn:(NSEventMaskLeftMouseUp | NSEventMaskRightMouseUp)];
}

static void statusDrawHand(CGContextRef ctx, CGFloat cx, CGFloat cy, CGFloat angle, CGFloat length, CGFloat width) {
    CGFloat ex = cx + length * sin(angle);
    CGFloat ey = cy + length * cos(angle);
    CGContextSetLineWidth(ctx, width);
    CGContextSetLineCap(ctx, kCGLineCapRound);
    CGContextMoveToPoint(ctx, cx, cy);
    CGContextAddLineToPoint(ctx, ex, ey);
    CGContextStrokePath(ctx);
}

- (NSImage *)drawStatusIcon {
    CGFloat sz = 18.0;
    NSImage *img = [[NSImage alloc] initWithSize:NSMakeSize(sz, sz)];
    [img lockFocus];

    CGContextRef ctx = [[NSGraphicsContext currentContext] CGContext];
    CGFloat cx = sz / 2.0, cy = sz / 2.0;
    CGFloat outerR = sz / 2.0 - 0.5;
    CGFloat ringThick = 1.8;
    CGFloat faceR = outerR - ringThick - 0.3;

    NSColor *ringCol = [NSColor colorWithRed:48/255.0 green:110/255.0 blue:200/255.0 alpha:1.0];
    NSColor *faceCol = [NSColor colorWithRed:246/255.0 green:232/255.0 blue:200/255.0 alpha:1.0];
    NSColor *handCol = [NSColor colorWithRed:28/255.0 green:40/255.0 blue:72/255.0 alpha:1.0];

    [ringCol setFill];
    CGContextFillEllipseInRect(ctx, CGRectMake(cx - outerR, cy - outerR, outerR * 2, outerR * 2));

    [faceCol setFill];
    CGContextFillEllipseInRect(ctx, CGRectMake(cx - faceR, cy - faceR, faceR * 2, faceR * 2));

    [handCol setStroke];
    statusDrawHand(ctx, cx, cy, 5 * M_PI / 3, faceR * 0.5, 1.5);
    statusDrawHand(ctx, cx, cy, M_PI / 3, faceR * 0.72, 1.0);

    [handCol setFill];
    CGFloat dotR = 1.0;
    CGContextFillEllipseInRect(ctx, CGRectMake(cx - dotR, cy - dotR, dotR * 2, dotR * 2));

    [img unlockFocus];
    return img;
}

- (void)statusItemClicked:(id)sender {
    NSEvent *event = [NSApp currentEvent];
    if (event.type == NSEventTypeRightMouseUp) {
        [self showContextMenuAtStatusItem];
    } else {
        self.isHidden = !self.isHidden;
        [self applyDockLayout];
    }
}

- (void)showContextMenuAtStatusItem {
    NSMenu *menu = [self buildMenu];
    menu.delegate = (id<NSMenuDelegate>)self;
    self.statusItem.menu = menu;
    [self.statusItem.button performClick:nil];
}

- (void)menuDidClose:(NSMenu *)menu {
    if (self.statusItem.menu == menu) {
        self.statusItem.menu = nil;
    }
}

#pragma mark - Global Hotkey

static OSStatus hotkeyHandler(EventHandlerCallRef nextHandler, EventRef theEvent, void *userData) {
    ClockWindow *cw = (__bridge ClockWindow *)userData;
    dispatch_async(dispatch_get_main_queue(), ^{
        cw.isHidden = !cw.isHidden;
        [cw applyDockLayout];
    });
    return noErr;
}

- (void)registerHotkey {
    EventTypeSpec eventType = {kEventClassKeyboard, kEventHotKeyPressed};
    InstallApplicationEventHandler(&hotkeyHandler, 1, &eventType, (__bridge void *)self, NULL);

    EventHotKeyID hotkeyID = {'DTCK', 1};
    RegisterEventHotKey(kVK_ANSI_T,
                        cmdKey | optionKey,
                        hotkeyID,
                        GetApplicationEventTarget(),
                        0,
                        &sHotkeyRef);
}

- (void)unregisterHotkey {
    if (sHotkeyRef) {
        UnregisterEventHotKey(sHotkeyRef);
        sHotkeyRef = NULL;
    }
}

@end
