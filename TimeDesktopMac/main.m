#import <Cocoa/Cocoa.h>
#import "ClockWindow.h"
#import "NetTimeSync.h"

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property (nonatomic, strong) ClockWindow *clockWindow;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    AppState *state = [AppState load];

    self.clockWindow = [[ClockWindow alloc] initWithState:state];
    [self.clockWindow setupStatusItem];
    [self.clockWindow registerHotkey];
    [self.clockWindow applyDockLayout];

    self.clockWindow.refreshTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                                    target:self
                                                                  selector:@selector(timerTick)
                                                                  userInfo:nil
                                                                   repeats:YES];
    self.clockWindow.refreshTimer.tolerance = 0.1;

    [[NetTimeSync shared] startSync];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(screenChanged:)
                                                 name:NSApplicationDidChangeScreenParametersNotification
                                               object:nil];
}

- (void)timerTick {
    [self.clockWindow refreshDisplay];
}

- (void)screenChanged:(NSNotification *)note {
    if (self.clockWindow.state.dockMode) {
        [self.clockWindow applyDockLayout];
    }
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    [self.clockWindow unregisterHotkey];
    [[NetTimeSync shared] stopSync];
    [self.clockWindow.state save];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app {
    return NO;
}

@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        AppDelegate *delegate = [[AppDelegate alloc] init];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
