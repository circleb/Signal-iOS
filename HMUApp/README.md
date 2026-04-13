# HMU Chat — Standalone App

A lightweight standalone iOS app containing the Homestead Heritage SSO (HCP) authentication layer, extracted from the main HCP Signal fork.

## What This Is

This app handles **Heritage Keycloak SSO authentication** and provides a member profile/directory experience — without the full Signal messaging stack.

## Stack

- Swift 5.9+ / iOS 16+
- SwiftUI (no UIKit Signal dependencies)
- `AppAuth` via CocoaPods (Keycloak OAuth2/OIDC)
- `async/await` replacing PromiseKit

## Setup

```bash
cd HMUApp
pod install
open HMUApp.xcworkspace   # use the workspace, not .xcodeproj
```

## Project Structure

```
HMUApp/
├── App/
│   ├── HMUApp.swift          # @main entry point
│   ├── AppDelegate.swift     # OAuth URL callback handler
│   ├── AuthStateManager.swift # ObservableObject for auth state
│   ├── Extensions.swift      # Color.hcpBlue etc.
│   └── Info.plist
├── SSO/
│   ├── SSOConfig.swift       # Keycloak endpoints & scopes
│   ├── SSOService.swift      # async/await OAuth2 flow
│   ├── SSOUserInfo.swift     # User data model
│   ├── SSOUserInfoStore.swift # UserDefaults persistence
│   └── SSORoleManager.swift  # Role/feature gating
└── Views/
    ├── ContentView.swift     # Root: switches Login ↔ Home
    ├── LoginView.swift       # SSO sign-in screen
    ├── HomeView.swift        # Post-auth home + sign-out
    ├── WebSheetView.swift    # WKWebView for heritage URLs
    └── AvatarView.swift      # Initials avatar
```

## OAuth Redirect URI

The app registers the `hmuchat://oauth/callback` URL scheme. After `pod install`, make sure the bundle ID and redirect URI in `SSOConfig.swift` match your Keycloak client configuration.

## Differences From the HCP Signal Fork

| Signal HCP fork | HMU standalone |
|---|---|
| PromiseKit | `async/await` |
| `OWSViewController` | `UIViewController` / SwiftUI |
| `SignalServiceKit.Logger` | removed (use Xcode console) |
| PureLayout | SwiftUI layout |
| Full Signal messaging stack | Removed |
