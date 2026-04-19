#import <Cocoa/Cocoa.h>
#include <math.h>

static NSColor *ringColor, *faceColor, *handColor, *tickColor, *shadowColor;

static void initColors(void) {
    ringColor   = [NSColor colorWithRed:48/255.0 green:110/255.0 blue:200/255.0 alpha:1.0];
    faceColor   = [NSColor colorWithRed:246/255.0 green:232/255.0 blue:200/255.0 alpha:1.0];
    handColor   = [NSColor colorWithRed:28/255.0 green:40/255.0 blue:72/255.0 alpha:1.0];
    tickColor   = [NSColor colorWithRed:120/255.0 green:95/255.0 blue:55/255.0 alpha:1.0];
    shadowColor = [NSColor colorWithRed:0 green:0 blue:0 alpha:0.15];
}

static void drawHand(CGContextRef ctx, CGFloat cx, CGFloat cy, CGFloat angle, CGFloat length, CGFloat width) {
    CGFloat ex = cx + length * sin(angle);
    CGFloat ey = cy + length * cos(angle);
    CGContextSetLineWidth(ctx, width);
    CGContextSetLineCap(ctx, kCGLineCapRound);
    CGContextMoveToPoint(ctx, cx, cy);
    CGContextAddLineToPoint(ctx, ex, ey);
    CGContextStrokePath(ctx);
}

static NSImage *drawClockIcon(CGFloat size) {
    NSImage *img = [[NSImage alloc] initWithSize:NSMakeSize(size, size)];
    [img lockFocus];

    CGContextRef ctx = [[NSGraphicsContext currentContext] CGContext];
    CGFloat cx = size / 2.0, cy = size / 2.0;
    CGFloat outerR = size / 2.0 - (size * 0.02);
    CGFloat ringThick = MAX(1.5, size * 0.08);
    CGFloat faceR = outerR - ringThick - MAX(0.5, size * 0.01);

    // outer ring
    [ringColor setFill];
    CGContextFillEllipseInRect(ctx, CGRectMake(cx - outerR, cy - outerR, outerR * 2, outerR * 2));

    // face
    [faceColor setFill];
    CGContextFillEllipseInRect(ctx, CGRectMake(cx - faceR, cy - faceR, faceR * 2, faceR * 2));

    // inner shadow ring
    if (size >= 32) {
        CGFloat shadowR = faceR - MAX(1, size * 0.02);
        CGContextSetLineWidth(ctx, MAX(1, size * 0.015));
        [shadowColor setStroke];
        CGContextStrokeEllipseInRect(ctx, CGRectMake(cx - shadowR, cy - shadowR, shadowR * 2, shadowR * 2));
    }

    // tick marks
    if (size >= 24) {
        CGFloat tickR = faceR * 0.82;
        for (int i = 0; i < 12; i++) {
            CGFloat ang = -M_PI / 2 + i * M_PI / 6;
            CGFloat tx = cx + tickR * cos(ang);
            CGFloat ty = cy + tickR * sin(ang);
            CGFloat r = MAX(0.8, size * 0.04);
            if (i % 3 == 0) r = MAX(1.0, size * 0.055);
            [tickColor setFill];
            CGContextFillEllipseInRect(ctx, CGRectMake(tx - r, ty - r, r * 2, r * 2));
        }
    }

    // hands at 10:10
    CGFloat hourAng = 5 * M_PI / 3;
    CGFloat minAng = M_PI / 3;
    CGFloat hourLen = faceR * 0.50;
    CGFloat minLen = faceR * 0.72;
    CGFloat hourThick = MAX(1.5, size * 0.07);
    CGFloat minThick = MAX(1.0, size * 0.055);

    [handColor setStroke];
    drawHand(ctx, cx, cy, hourAng, hourLen, hourThick);
    drawHand(ctx, cx, cy, minAng, minLen, minThick);

    // center dot
    CGFloat dotR = MAX(1.0, size * 0.05);
    [handColor setFill];
    CGContextFillEllipseInRect(ctx, CGRectMake(cx - dotR, cy - dotR, dotR * 2, dotR * 2));

    [img unlockFocus];
    return img;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        initColors();

        NSString *iconsetPath = @"AppIcon.iconset";
        NSFileManager *fm = [NSFileManager defaultManager];
        [fm createDirectoryAtPath:iconsetPath withIntermediateDirectories:YES attributes:nil error:nil];

        struct { int size; NSString *name; } entries[] = {
            {16,   @"icon_16x16.png"},
            {32,   @"icon_16x16@2x.png"},
            {32,   @"icon_32x32.png"},
            {64,   @"icon_32x32@2x.png"},
            {128,  @"icon_128x128.png"},
            {256,  @"icon_128x128@2x.png"},
            {256,  @"icon_256x256.png"},
            {512,  @"icon_256x256@2x.png"},
            {512,  @"icon_512x512.png"},
            {1024, @"icon_512x512@2x.png"},
        };

        for (int i = 0; i < 10; i++) {
            int sz = entries[i].size;
            NSImage *icon = drawClockIcon(sz);
            NSBitmapImageRep *rep = [[NSBitmapImageRep alloc]
                initWithBitmapDataPlanes:NULL
                              pixelsWide:sz
                              pixelsHigh:sz
                           bitsPerSample:8
                         samplesPerPixel:4
                                hasAlpha:YES
                                isPlanar:NO
                          colorSpaceName:NSCalibratedRGBColorSpace
                             bytesPerRow:0
                            bitsPerPixel:0];
            rep.size = NSMakeSize(sz, sz);

            [NSGraphicsContext saveGraphicsState];
            NSGraphicsContext *gctx = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
            [NSGraphicsContext setCurrentContext:gctx];
            [icon drawInRect:NSMakeRect(0, 0, sz, sz)
                    fromRect:NSZeroRect
                   operation:NSCompositingOperationCopy
                    fraction:1.0];
            [NSGraphicsContext restoreGraphicsState];

            NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
            NSString *path = [iconsetPath stringByAppendingPathComponent:entries[i].name];
            [png writeToFile:path atomically:YES];
            fprintf(stderr, "  wrote %s (%dx%d)\n", path.UTF8String, sz, sz);
        }

        fprintf(stderr, "Running iconutil...\n");
        NSTask *task = [[NSTask alloc] init];
        task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/iconutil"];
        task.arguments = @[@"-c", @"icns", iconsetPath];
        NSError *err = nil;
        [task launchAndReturnError:&err];
        if (err) {
            fprintf(stderr, "iconutil launch error: %s\n", err.localizedDescription.UTF8String);
            return 1;
        }
        [task waitUntilExit];
        if (task.terminationStatus != 0) {
            fprintf(stderr, "iconutil failed with status %d\n", task.terminationStatus);
            return 1;
        }

        [fm removeItemAtPath:iconsetPath error:nil];
        fprintf(stderr, "Generated AppIcon.icns\n");
    }
    return 0;
}
