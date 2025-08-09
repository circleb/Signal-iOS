# Signal Onboarding Flow Documentation

## Current Onboarding Flow

This document outlines the current onboarding flow for the Signal app, including all possible pathways and view sequences.

### Overview

The onboarding flow is managed by the `RegistrationCoordinator` and follows different pathways based on the user's situation. The main pathways are:

1. **Opening Pathway** - Initial screens for new users
2. **Quick Restore Pathway** - For users with their old device
3. **Manual Restore Pathway** - For users without their old device but want to restore
4. **Session Pathway** - Standard SMS verification flow
5. **Profile Setup Pathway** - Post-registration configuration

### Current Flow Sequence

#### 1. Opening Pathway (New Users)

**Standard Registration Flow:**

1. **Registration Splash** (`registrationSplash`)

   - Welcome screen with app introduction
   - For Heritage Signal: Shows SSO splash (`ssoRegistrationSplash`)
   - User can choose to have old device or not

2. **Permissions** (`permissions`) - _Conditional_

   - Contacts permission request
   - Only shown if permissions are needed

3. **Phone Number Entry** (`phoneNumberEntry`)

   - User enters their phone number
   - Validation and confirmation required

4. **Verification Code Entry** (`verificationCodeEntry`)

   - SMS/voice code verification
   - Can include captcha challenges (`captchaChallenge`)

5. **Transfer Selection** (`transferSelection`) - _Conditional_

   - Only if device transfer is possible
   - User chooses to transfer or skip

6. **PIN Entry** (`pinEntry`) - _Conditional_

   - Creating new PIN or confirming existing PIN
   - Can be skipped in some cases

7. **Registration Complete** → Move to Post-Registration

#### 2. Quick Restore Pathway (Users with Old Device)

1. **Registration Splash** (same as above)

2. **Scan QR Code** (`scanQuickRegistrationQrCode`)

   - QR code for device-to-device transfer

3. **Device Transfer** (`deviceTransfer`) - _Conditional_

   - Transfer status and progress

4. **Choose Restore Method** (`chooseRestoreMethod`) - _Conditional_

   - Options for restore/transfer

5. **Confirm Restore** (`confirmRestoreFromBackup`) - _Conditional_

   - Backup confirmation if applicable

6. **Registration Complete** → Move to Post-Registration

#### 3. Manual Restore Pathway (Users without Old Device)

1. **Registration Splash** (same as above)

2. **Choose Restore Method** (`chooseRestoreMethod`)

3. **Phone Number Entry** (`phoneNumberEntry`) - _Conditional_

   - If phone number not already known

4. **Enter Backup Key** (`enterBackupKey`)

   - Manual backup key entry

5. **Registration Complete** → Move to Post-Registration

#### 4. Post-Registration Flow (All Pathways)

After successful registration, users go through:

1. **Phone Number Discoverability** (`phoneNumberDiscoverability`) - _Conditional_

   - Choose who can find them by phone number
   - Everybody or Nobody options
   - Skipped during re-registration

2. **Profile Setup** (`setupProfile`) - _Conditional_

   - Set display name and avatar
   - Phone number privacy settings
   - Skipped during re-registration

3. **Done** (`done`)
   - Registration complete, enter main app

### Error Handling and Special Cases

#### Error States

- **Session Invalidated** (`showErrorSheet(.sessionInvalidated)`)
- **Verification Code Issues** (`showErrorSheet(.verificationCodeSubmissionUnavailable)`)
- **Network Errors** (`showErrorSheet(.networkError)`)
- **Generic Errors** (`showErrorSheet(.genericError)`)

#### Special Flows

- **PIN Attempts Exhausted** (`pinAttemptsExhaustedWithoutReglock`)
- **Registration Lock Timeout** (`reglockTimeout`)
- **App Update Required** (`appUpdateBanner`)

### View Controllers and UI Components

#### Main View Controllers

- `RegistrationSplashViewController` - Initial welcome screen
- `SSORegistrationSplashViewController` - Heritage SSO splash
- `RegistrationPermissionsViewController` - Permissions request
- `RegistrationPhoneNumberViewController` - Phone number entry
- `RegistrationVerificationViewController` - Code verification
- `RegistrationPinViewController` - PIN creation/entry
- `RegistrationProfileViewController` - Profile setup
- `RegistrationPhoneNumberDiscoverabilityViewController` - Privacy settings

#### Navigation

- `RegistrationNavigationController` - Manages view transitions
- `RegistrationCoordinatorImpl` - Orchestrates flow logic

### Conditional Logic

The flow adapts based on:

- **Registration Mode**: New registration, re-registration, or phone number change
- **Device State**: Whether user has old device
- **Backup Availability**: Whether backup exists and is accessible
- **User Preferences**: PIN requirements, privacy settings
- **Network Conditions**: SMS delivery, server connectivity

---

## Desired Onboarding Flow Changes

### Proposed Changes

**Current Flow Issues:**

- The current flow requires the user to enter their phone number and verification code before they can see the web apps. This is not ideal because the user may not have a phone number or may not want to enter it.

**Desired Flow:**

1. The user should be required to sign in using the Heritage SSO.
2. The main app will load, but chats, stories, and calls will be disabled.
3. The user will be able to see the web apps and use them.
4. The user will be able to sign out of the app and sign in again using the Heritage SSO.
5. The tab buttons (chats, stories, calls) will remain visible but will show an onboarding prompt when tapped, allowing users to start the full onboarding flow.

### Integration Guide

**Key Changes Required:**

1. **SSO-First Authentication Flow**

   - Modify app launch logic to require SSO authentication before entering main app
   - Create a new "limited registration" state that allows web app access without full phone verification
   - Update `TSAccountManager` to support SSO-only registration state

2. **Limited App State**

   - Disable chats, stories, and calls functionality when in limited registration state
   - Keep tab buttons visible but show onboarding prompt when tapped
   - Modify main app UI to show appropriate messaging for limited state
   - Ensure web apps remain accessible in limited state

3. **Onboarding Flow Integration**
   - Add onboarding prompt that appears when any main tab (chats, stories, calls) is tapped in limited state
   - Preserve existing onboarding flow for when users choose to complete full registration
   - Handle transition from limited to full registration state

**Files to Modify:**

**Core Registration Logic:**

- `SignalServiceKit/Account/TSAccountManager/TSRegistrationState.swift` - Add new SSO-only registration state
- `SignalServiceKit/Account/TSAccountManager/TSAccountManagerImpl.swift` - Handle SSO-only state management
- `Signal/AppLaunch/AppDelegate.swift` - Update launch logic to check for SSO authentication first
- `Signal/Registration/RegistrationCoordinatorImpl.swift` - Add logic for limited registration completion

**SSO Integration:**

- `Signal/Registration/UserInterface/SSORegistrationSplashViewController.swift` - Ensure proper SSO flow
- `Signal/Registration/UserInterface/SSOAuthenticationViewController.swift` - Handle SSO authentication
- `Signal/SSO/` - Review and update SSO service integration

**Main App UI:**

- `Signal/ConversationView/` - Add onboarding prompt for chats tab
- `Signal/Calls/` - Add onboarding prompt for calls tab
- `Signal/Stories/` - Add onboarding prompt for stories tab
- `SignalUI/` - Update UI components to handle limited state and tab interactions

**Feature Flags and Configuration:**

- `SignalServiceKit/Environment/` - Add feature flags for limited registration mode
- `Config/` - Update configuration for Heritage-specific settings

**New Components Needed:**

- Limited registration state manager
- Onboarding prompt view controller (reusable for all tabs)
- Tab interaction handlers for limited state
- SSO-only registration coordinator

**Testing Considerations:**

- SSO authentication flow with various Heritage account states
- Limited app functionality (chats/stories/calls show onboarding prompt)
- Tab button interactions in limited state
- Web app accessibility in limited state
- Transition from limited to full registration
- Sign out and sign back in flow
- Edge cases: SSO failures, network issues, account restrictions
- Integration with existing onboarding flow
- Backward compatibility with existing registered users

**Implementation Phases:**

1. **Phase 1**: Implement SSO-first authentication and limited registration state
2. **Phase 2**: Add onboarding prompts for all main tabs (chats, stories, calls)
3. **Phase 3**: Implement tab interaction handlers for limited state
4. **Phase 4**: Test and refine transition flows

---

## Implementation Checklist

- [ ] Add new SSO-only registration state to `TSRegistrationState`
- [ ] Update `TSAccountManager` to handle limited registration state
- [ ] Modify app launch logic in `AppDelegate` for SSO-first flow
- [ ] Create limited registration state manager
- [ ] Add onboarding prompts for all main tabs (chats, stories, calls)
- [ ] Create reusable onboarding prompt view controller
- [ ] Update SSO integration components
- [ ] Add configuration for Heritage-specific settings
- [ ] Test SSO authentication flow
- [ ] Test limited app functionality (tab interactions)
- [ ] Test transition to full registration
- [ ] Test sign out/sign in flow
- [ ] Update documentation
