# MacAwake

macOS menu bar app that keeps the Mac awake by driving [`caffeinate(8)`](https://www.unix.com/man-page/osx/8/caffeinate/).

Toggle from the menu extra (cup icon) or by right-clicking the status item. Configure sleep assertions, timed sessions, wait-for-process, and launch-at-login from the popover or Settings.

## Requirements

- macOS 15+
- Xcode 26.6+

## Build

Open `MacAwake.xcodeproj` and run the **MacAwake** scheme, or:

```sh
xcodebuild -scheme MacAwake -configuration Release
```

Regenerate the Xcode project from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen) if you change project settings.
