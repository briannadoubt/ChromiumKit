#import <Cocoa/Cocoa.h>

@protocol CrAppProtocol
- (BOOL)isHandlingSendEvent;
@end

@protocol CrAppControlProtocol <CrAppProtocol>
- (void)setHandlingSendEvent:(BOOL)handlingSendEvent;
@end

@protocol CefAppProtocol <CrAppControlProtocol>
@end

@interface ChromiumKitApplication : NSApplication <CefAppProtocol>
@end

@implementation ChromiumKitApplication {
  BOOL _handlingSendEvent;
}

- (BOOL)isHandlingSendEvent {
  return _handlingSendEvent;
}

- (void)setHandlingSendEvent:(BOOL)handlingSendEvent {
  _handlingSendEvent = handlingSendEvent;
}

- (void)sendEvent:(NSEvent *)event {
  BOOL previous = _handlingSendEvent;
  _handlingSendEvent = YES;
  [super sendEvent:event];
  _handlingSendEvent = previous;
}

@end
