#ifndef TargetKeyboardEventBridge_h
#define TargetKeyboardEventBridge_h

#include <ApplicationServices/ApplicationServices.h>
#include <stdbool.h>

AXError VoiceInkPostTargetVirtualKey(
    AXUIElementRef application,
    CGKeyCode virtualKey,
    bool keyDown
);

#endif
