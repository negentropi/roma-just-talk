#include "TargetKeyboardEventBridge.h"

AXError VoiceInkPostTargetVirtualKey(
    AXUIElementRef application,
    CGKeyCode virtualKey,
    bool keyDown
) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    // The deprecated C API remains the only Accessibility keyboard route bound to one app.
    AXError result = AXUIElementPostKeyboardEvent(application, 0, virtualKey, keyDown);
#pragma clang diagnostic pop
    return result;
}
