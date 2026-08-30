# Building VoiceInk

This guide provides detailed instructions for building VoiceInk from source.

## Prerequisites

Before you begin, ensure you have:
- macOS 14.4 or later
- Xcode (latest version recommended)
- Swift (latest version recommended)
- Git (for cloning repositories)

## Quick Start with Makefile (Recommended)

The easiest way to build VoiceInk is using the included Makefile, which automates the entire build process including building and statically linking Whisper.

### Simple Build Commands

```bash
# Clone the repository
git clone https://github.com/Beingpax/VoiceInk.git
cd VoiceInk

# Build everything (recommended for first-time setup)
make all

# Or for development (build and run)
make dev
```

### Available Makefile Commands

- `make check` or `make healthcheck` - Verify all required tools are installed
- `make whisper` - Clone and build the static whisper.cpp XCFramework automatically
- `make setup` - Prepare the whisper framework for linking
- `make build` - Build the VoiceInk Xcode project
- `make local` - Build for local use (no Apple Developer certificate needed)
- `make run` - Launch the built VoiceInk app
- `make dev` - Build and run (ideal for development workflow)
- `make all` - Complete build process (default)
- `make clean` - Remove build artifacts and dependencies
- `make help` - Show all available commands

### How the Makefile Helps

The Makefile automatically:
1. **Manages Dependencies**: Creates a dedicated `~/VoiceInk-Dependencies` directory for all external frameworks
2. **Builds Whisper Framework**: Clones whisper.cpp and builds every XCFramework slice as a static archive
3. **Handles Framework Linking**: Links Whisper into each app executable instead of embedding `whisper.framework`
4. **Verifies Prerequisites**: Checks that git, xcodebuild, and swift are installed before building
5. **Streamlines Development**: Provides convenient shortcuts for common development tasks

This approach ensures consistent builds across different machines and eliminates manual framework setup errors.

---

## Building for Local Use (No Apple Developer Certificate)

If you don't have an Apple Developer certificate, use `make local`:

```bash
git clone https://github.com/Beingpax/VoiceInk.git
cd VoiceInk
make local
open ~/Downloads/VoiceInk.app
```

This builds VoiceInk with ad-hoc signing using a separate build configuration (`LocalBuild.xcconfig`) that requires no Apple Developer account.
Whisper is part of the app executable, so the local build does not need a separately signed Whisper dynamic framework at launch.
The local entitlement set disables Hardened Runtime Library Validation because the app still loads the bundled MediaRemoteAdapter and Sparkle frameworks. Without a Developer ID Team ID, macOS 26.4.1 can reject those separately signed objects when Gatekeeper runs the app through App Translocation. Normal certificate-signed builds keep Library Validation enabled.

### How It Works

The `make local` command uses:
- `LocalBuild.xcconfig` to override signing and entitlements settings
- `VoiceInk.local.entitlements` (stripped-down, no CloudKit/keychain groups)
- `scripts/verify-adhoc-library-validation.sh` to reject an ad-hoc app that loads bundled code without the required local entitlement
- `LOCAL_BUILD` Swift compilation flag for conditional code paths

Your normal `make all` / `make build` commands are completely unaffected.

---

## Manual Build Process (Alternative)

If you prefer to build manually or need more control over the build process, follow these steps:

### Building whisper.cpp Framework

1. Clone and build whisper.cpp:
```bash
git clone https://github.com/ggerganov/whisper.cpp.git
cd whisper.cpp
BUILD_STATIC_XCFRAMEWORK=ON ./build-xcframework.sh
```
This will create the XCFramework at `build-apple/whisper.xcframework`.

### Building VoiceInk

1. Clone the VoiceInk repository:
```bash
git clone https://github.com/Beingpax/VoiceInk.git
cd VoiceInk
```

2. Add the whisper.xcframework to your project for linking without embedding it:
   - Drag and drop `../whisper.cpp/build-apple/whisper.xcframework` into the project navigator, or
   - Add it manually in the "Frameworks, Libraries, and Embedded Content" section with "Do Not Embed"
   - Keep `CoreML.framework` linked because the static Whisper archive includes its CoreML implementation

3. Build and Run
   - Build the project using Cmd+B or Product > Build
   - Run the project using Cmd+R or Product > Run

## Development Setup

1. **Xcode Configuration**
   - Ensure you have the latest Xcode version
   - Install any required Xcode Command Line Tools

2. **Dependencies**
   - The project uses [whisper.cpp](https://github.com/ggerganov/whisper.cpp) for transcription
   - Ensure the static whisper.xcframework is linked but not embedded in your Xcode project
   - Test the whisper.cpp installation independently before proceeding

3. **Building for Development**
   - Use the Debug configuration for development
   - Enable relevant debugging options in Xcode

4. **Testing**
   - Run the test suite before making changes
   - Ensure all tests pass after your modifications

## Troubleshooting

If you encounter any build issues:
1. Clean the build folder (Cmd+Shift+K)
2. Clean the build cache (Cmd+Shift+K twice)
3. Check Xcode and macOS versions
4. Verify all dependencies are properly installed
5. Make sure whisper.xcframework is properly built and linked
6. Run `bash scripts/verify-static-whisper-xcframework.sh ~/VoiceInk-Dependencies/whisper.cpp/build-apple/whisper.xcframework`
7. After building, run `make static-whisper-app-check`
8. Run `make adhoc-library-validation-check` to verify the local app's signature and bundled-code contract

For more help, please check the [issues](https://github.com/Beingpax/VoiceInk/issues) section or create a new issue.
