# NativeWatch ARM caller correction

This fork is based on upstream KSCrash 2.6.0 (3f77f379c2db001e0c261c2a51b7e2b115d31f91).
It corrects three issues demonstrated by a Release Swift fatalError and real
compact/DWARF assembly fixtures:

- Full unwinding emits the caller recovered from unwind metadata. It does not
  emit a stale LR and then advance past the saved caller. The interrupted PC is
  exact; subsequent return addresses use the existing lookup adjustment.
- DWARF PC-relative FDE locations are based on the encoded location field,
  rather than its preceding CIE-pointer field. This preserves function boundaries.
- DWARF SameValue rules use the supplied SP/FP/LR when that register is available.
  An unchanged FP remains unrestored; undefined/unavailable rules still fail.

The explicit frame-pointer-only cursor retains its historical LR behavior for
compatibility, except when LR duplicates PC. No private monitor callbacks or
custom NativeWatch unwinder are involved.

Verification: 632 core XCTest tests, 2 existing skips, zero failures on Apple
Silicon macOS/Xcode 27.1. New regressions cover saved callers, stale LR, compact
and DWARF frameless leaves, unchanged/undefined registers, exact FDE boundaries,
and reset/re-walk consistency. The original PC==LR regression fails on upstream.

A real optimized iPhone 17 Pro/iOS 26.5 Simulator Release app then captured its
Swift fatal caller, and the actual matching dSYM resolved NativeWatchFunctions.swift
line 41. Its Objective-C exception origin resolved to line 48. This establishes
those simulator mechanisms; physical arm64e/PAC acceptance is separate.

Reproduce the core suite from this checkout:

```sh
xcodebuild test -scheme KSCrash-Package -destination 'platform=macOS' \
  -only-testing:KSCrashRecordingCoreTests -parallel-testing-enabled NO
```

The NativeWatch integration and acceptance evidence live in
https://github.com/zinxan/native.watch/pull/36.
