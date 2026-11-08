# FinFlow · iPhone + iPad + Mac

SwiftUI shared app and single authenticated backend. iPhone uses 5 tabs. iPad with regular width and Mac Catalyst use NavigationSplitView with sidebar. TARGETED_DEVICE_FAMILY 1,2 remains supported; SUPPORTS_MACCATALYST enabled. CI builds iOS simulator and Mac Catalyst, and runs the app in an iPad simulator with screenshot. macOS Catalyst is not a native AppKit target. Need hands-on keyboard, VoiceOver, window resize, TestFlight, Mac signing and distribution tests before declaring store ready. No Student Beta, no database change. Stacked PR #6 -> #5.
