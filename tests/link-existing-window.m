#import "Patches/LinkExistingWindow/LinkExistingWindow.m"

DPPatch DPLittleDia, DPLittleDiaFollowRules;

static NSMutableArray<NSString *> *gOpened;
static int gActivations;

@interface FakeEvent : NSObject <NSCopying>
@property (nonatomic, strong) NSAppleEventDescriptor *inner;
@property (nonatomic) pid_t sender;
@end
@implementation FakeEvent
- (AEEventClass)eventClass { return self.inner.eventClass; }
- (AEEventID)eventID { return self.inner.eventID; }
- (NSAppleEventDescriptor *)paramDescriptorForKeyword:(AEKeyword)keyword { return [self.inner paramDescriptorForKeyword:keyword]; }
- (NSAppleEventDescriptor *)attributeDescriptorForKeyword:(AEKeyword)keyword {
    return keyword == keySenderPIDAttr ? [NSAppleEventDescriptor descriptorWithInt32:self.sender] : [self.inner attributeDescriptorForKeyword:keyword];
}
- (id)copyWithZone:(NSZone *)zone {
    FakeEvent *copy = [FakeEvent new];
    copy.inner = [self.inner copy];
    copy.sender = self.sender;
    return copy;
}
@end

@interface _TtC13OpenURLClient19OpenURLEventManager : NSObject
@end
@implementation _TtC13OpenURLClient19OpenURLEventManager
- (void)handleEvent:(NSAppleEventDescriptor *)event withReplyEvent:(NSAppleEventDescriptor *)reply {
    [gOpened addObject:[event paramDescriptorForKeyword:keyDirectObject].stringValue ?: @"(no address)"];
}
@end

@interface _TtC15BoostBrowserMac11AppDelegate : NSObject
@end
@implementation _TtC15BoostBrowserMac11AppDelegate
- (void)application:(NSApplication *)app openURLs:(NSArray<NSURL *> *)urls {
    for (NSURL *url in urls) [gOpened addObject:url.absoluteString];
}
@end

@interface _TtC6Window14PlatformWindow : NSWindow
@property BOOL here, shown, small;
@property int fronted;
@end
@implementation _TtC6Window14PlatformWindow
- (BOOL)isOnActiveSpace { return self.here; }
- (BOOL)isVisible { return self.shown; }
- (BOOL)isMiniaturized { return self.small; }
- (void)makeKeyAndOrderFront:(id)sender { self.fronted++; }
@end

static void DPApp_activate(id self, SEL _cmd, BOOL ignoring) { gActivations++; }

static int failures;

static void expect(BOOL ok, NSString *what) {
    if (ok) return;
    failures++;
    printf("FAIL: %s\n", what.UTF8String);
}

static NSAppleEventDescriptor *makeEvent(AEEventID eventID, NSString *address, pid_t sender) {
    NSAppleEventDescriptor *event = [NSAppleEventDescriptor appleEventWithEventClass:kInternetEventClass eventID:eventID
                                                                    targetDescriptor:NSAppleEventDescriptor.nullDescriptor
                                                                            returnID:kAutoGenerateReturnID transactionID:kAnyTransactionID];
    [event setParamDescriptor:[NSAppleEventDescriptor descriptorWithString:address] forKeyword:keyDirectObject];
    FakeEvent *wrapped = [FakeEvent new];
    wrapped.inner = event;
    wrapped.sender = sender;
    return (NSAppleEventDescriptor *)wrapped;
}

static void spin(NSTimeInterval seconds) {
    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
}

static void reset(_TtC6Window14PlatformWindow *window) {
    window.here = YES;
    spin(0.2);
    [gOpened removeAllObjects];
    gActivations = 0;
    window.here = NO;
    window.shown = YES;
    window.small = NO;
    window.fronted = 0;
    DPLinkExistingWindow.on = YES;
    DPLittleDia.on = NO;
    DPLittleDiaFollowRules.on = NO;
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        DPHookClass(NSApplication.class, @selector(activateIgnoringOtherApps:), (IMP)DPApp_activate);
        gOpened = [NSMutableArray array];
        DPInstallLinkExistingWindow();
        _TtC13OpenURLClient19OpenURLEventManager *manager = [_TtC13OpenURLClient19OpenURLEventManager new];
        _TtC15BoostBrowserMac11AppDelegate *delegate = [_TtC15BoostBrowserMac11AppDelegate new];
        NSAppleEventDescriptor *reply = [NSAppleEventDescriptor nullDescriptor];
        pid_t other = getpid() + 1;
        _TtC6Window14PlatformWindow *window = [[_TtC6Window14PlatformWindow alloc] initWithContentRect:NSMakeRect(-30000, -30000, 100, 100)
                                                                                           styleMask:NSWindowStyleMaskBorderless
                                                                                             backing:NSBackingStoreBuffered defer:YES];
        window.releasedWhenClosed = NO;

        reset(window);
        [manager handleEvent:makeEvent(kAEGetURL, @"https://example.com/elsewhere", other) withReplyEvent:reply];
        expect(gOpened.count == 0 && window.fronted == 1 && gActivations == 1,
               @"a link from another app shows Dia's window on the other Desktop before Dia gets the link, so Dia has no reason to make a new one");
        spin(0.2);
        expect(gOpened.count == 0, @"the link waits until that window is on the Desktop in front");
        window.here = YES;
        spin(0.2);
        expect([gOpened isEqualToArray:@[ @"https://example.com/elsewhere" ]] && window.fronted == 1, @"the link then reaches Dia once, with its address unchanged");

        reset(window);
        window.here = YES;
        [manager handleEvent:makeEvent(kAEGetURL, @"https://example.com/here", other) withReplyEvent:reply];
        expect(gOpened.count == 1 && window.fronted == 0 && gActivations == 0, @"a link opens as Dia opens it when Dia has a window on this Desktop");

        reset(window);
        [manager handleEvent:makeEvent(kAEGetURL, @"https://example.com/stuck", other) withReplyEvent:reply];
        spin(DPShowTries * 0.05 + 0.3);
        expect([gOpened isEqualToArray:@[ @"https://example.com/stuck" ]], @"a link still opens when macOS never brings the window to the front Desktop");

        reset(window);
        DPLinkExistingWindow.on = NO;
        [manager handleEvent:makeEvent(kAEGetURL, @"https://example.com/off", other) withReplyEvent:reply];
        expect(gOpened.count == 1 && window.fronted == 0, @"switched off, links go straight to Dia");

        reset(window);
        [manager handleEvent:makeEvent(kAEGetURL, @"https://example.com/self", getpid()) withReplyEvent:reply];
        expect(gOpened.count == 1 && window.fronted == 0, @"a link Dia sends itself is left alone");

        reset(window);
        [manager handleEvent:makeEvent('XXXX', @"https://example.com/other-event", other) withReplyEvent:reply];
        expect(gOpened.count == 1 && window.fronted == 0, @"events that aren't a link from another app are left alone");

        reset(window);
        DPLittleDia.on = YES;
        [manager handleEvent:makeEvent(kAEGetURL, @"https://example.com/little", other) withReplyEvent:reply];
        expect(gOpened.count == 1 && window.fronted == 0, @"Little Dia keeps links from other apps");
        DPLittleDiaFollowRules.on = YES;
        [manager handleEvent:makeEvent(kAEGetURL, @"https://example.com/rules", other) withReplyEvent:reply];
        expect(gOpened.count == 1 && window.fronted == 1, @"with Follow Link Rules, links open as tabs, so they go to the existing window");

        for (NSString *state in @[ @"minimized", @"hidden" ]) {
            reset(window);
            window.small = [state isEqualToString:@"minimized"];
            window.shown = ![state isEqualToString:@"hidden"];
            [manager handleEvent:makeEvent(kAEGetURL, @"https://example.com/none", other) withReplyEvent:reply];
            expect(gOpened.count == 1 && window.fronted == 0, [NSString stringWithFormat:@"a %@ window isn't brought forward", state]);
        }

        reset(window);
        [delegate application:NSApp openURLs:@[ [NSURL URLWithString:@"https://example.com/launch-services"] ]];
        expect(gOpened.count == 0 && window.fronted == 1, @"links handed to the app delegate show the existing window first too");
        window.here = YES;
        spin(0.2);
        expect([gOpened isEqualToArray:@[ @"https://example.com/launch-services" ]], @"and then open once");
    }
    if (failures) return 1;
    puts("PASS: links from other apps go to Dia's existing window on another Desktop");
    return 0;
}
