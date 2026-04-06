#import "AppKitShim.h"

#import <AppKit/AppKit.h>
#import <objc/runtime.h>

static const void *kCKHandlingSendEventKey = &kCKHandlingSendEventKey;

@interface NSApplication (ChromiumKitAppShim)
- (void)ck_chromiumKit_sendEvent:(NSEvent *)event;
@end

@implementation NSApplication (ChromiumKitAppShim)

- (BOOL)isHandlingSendEvent {
    return [objc_getAssociatedObject(self, kCKHandlingSendEventKey) boolValue];
}

- (void)setHandlingSendEvent:(BOOL)handlingSendEvent {
    objc_setAssociatedObject(
        self,
        kCKHandlingSendEventKey,
        @(handlingSendEvent),
        OBJC_ASSOCIATION_RETAIN_NONATOMIC
    );
}

- (void)ck_chromiumKit_sendEvent:(NSEvent *)event {
    BOOL previous = [self isHandlingSendEvent];
    [self setHandlingSendEvent:YES];
    [self ck_chromiumKit_sendEvent:event];
    [self setHandlingSendEvent:previous];
}

@end

void CKInstallApplicationShim(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class applicationClass = [NSApplication class];
        Method originalMethod = class_getInstanceMethod(applicationClass, @selector(sendEvent:));
        Method shimMethod = class_getInstanceMethod(applicationClass, @selector(ck_chromiumKit_sendEvent:));
        if (originalMethod != NULL && shimMethod != NULL) {
            method_exchangeImplementations(originalMethod, shimMethod);
        }
    });
}
