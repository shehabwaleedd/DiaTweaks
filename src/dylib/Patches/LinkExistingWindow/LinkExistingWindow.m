#import "Patches/LittleDia/LittleDia.h"
#import <Carbon/Carbon.h>

extern DPPatch DPLinkExistingWindow;

static const int DPShowTries = 40;

static BOOL DPIsOpenBrowserWindow(NSWindow *window) {
    return DPIsKind(window, DPDiaWindow) && window.visible && !window.miniaturized && window.level == NSNormalWindowLevel;
}

static NSWindow *DPWindowOnAnotherDesktop(void) {
    NSWindow *found = nil;
    for (NSArray<NSWindow *> *list in @[ NSApp.orderedWindows, NSApp.windows ])
        for (NSWindow *window in list) {
            if (!DPIsOpenBrowserWindow(window)) continue;
            if (window.onActiveSpace) return nil;
            if (!found) found = window;
        }
    return found;
}

static BOOL DPIsFromDia(NSAppleEventDescriptor *event) {
    return event && [event attributeDescriptorForKeyword:keySenderPIDAttr].int32Value == getpid();
}

static void DPOpenOnceShown(NSWindow *window, int tries, void (^open)(void)) {
    if (window.onActiveSpace || tries <= 0) return open();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 50 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ DPOpenOnceShown(window, tries - 1, open); });
}

static BOOL DPOpenInExistingWindow(void (^open)(void)) {
    if (!DPLinkExistingWindow.on || (DPLittleDia.on && !DPLittleDiaFollowRules.on)) return NO;
    NSWindow *window = DPWindowOnAnotherDesktop();
    if (!window) return NO;
    [NSApp activateIgnoringOtherApps:YES];
    [window makeKeyAndOrderFront:nil];
    DPOpenOnceShown(window, DPShowTries, open);
    return YES;
}

static void DPOpenURLEvents_existing(id self, SEL _cmd, NSAppleEventDescriptor *event, NSAppleEventDescriptor *reply) {
    BOOL link = event.eventClass == kInternetEventClass && event.eventID == kAEGetURL && !DPIsFromDia(event);
    NSAppleEventDescriptor *kept = link ? [event copy] : nil;
    BOOL waiting = kept && DPOpenInExistingWindow(^{
        DPCallOriginal(DPOpenURLEvents_existing, self, kept, [NSAppleEventDescriptor nullDescriptor]);
    });
    if (!waiting) DPCallOriginal(DPOpenURLEvents_existing, self, event, reply);
}

static void DPAppDelegate_openURLsExisting(id self, SEL _cmd, NSApplication *app, NSArray<NSURL *> *urls) {
    BOOL waiting = !DPIsFromDia(NSAppleEventManager.sharedAppleEventManager.currentAppleEvent) && DPOpenInExistingWindow(^{
        DPCallOriginal(DPAppDelegate_openURLsExisting, self, app, urls);
    });
    if (!waiting) DPCallOriginal(DPAppDelegate_openURLsExisting, self, app, urls);
}

static void DPInstallLinkExistingWindow(void) {
    DPHook(DPDiaOpenURLEvents, @selector(handleEvent:withReplyEvent:), (IMP)DPOpenURLEvents_existing);
    DPHook(DPDiaAppDelegate, @selector(application:openURLs:), (IMP)DPAppDelegate_openURLsExisting);
}

DP_PATCH(DPLinkExistingWindow) {
    .key = @"linkExistingWindow",
    .order = 99,
    .title = @"Links Open in Existing Window",
    .detail = @"A link from another app opens as a tab in the window Dia already has, even when that window is on another Desktop, instead of in a new window on the Desktop you’re on.",
    .symbol = @"macwindow.on.rectangle",
    .tint = @"systemYellowColor",
    .section = @"App",
    .classes = DPClasses(DPDiaAppDelegate, DPDiaOpenURLEvents, DPDiaWindow),
    .install = DPInstallLinkExistingWindow,
};
