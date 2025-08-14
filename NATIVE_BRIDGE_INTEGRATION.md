# Native Bridge Integration for Web Apps

## Overview

The WebAppWebViewController has been enhanced to integrate with the Native Bridge API for seamless authentication when opening web apps. This integration allows users to be automatically authenticated when they open web apps through the Signal app, using their existing SSO credentials.

## How It Works

### 1. Token Detection

When a user opens a web app, the system first checks if they have a valid SSO access token stored locally.

### 2. Native Bridge Authentication

If a token is available, the app calls the Native Bridge API with:

- **URL**: `https://my.homesteadheritage.org/api/v2/native-bridge.php`
- **Method**: GET
- **Headers**: `Authorization: Bearer <access_token>`
- **Parameters**: `target=<web_app_url>`

### 3. Token Exchange

The Native Bridge:

- Validates the provided access token
- Exchanges it for a new token with the appropriate audience for the target web app
- Returns either a 302 redirect or JSON response with the authenticated URL

### 4. Web App Loading

The app then loads the web app using the authenticated URL returned by the Native Bridge.

## Implementation Details

### Key Components

1. **SSOUserInfoStore**: Provides access to stored SSO user information and access tokens
2. **Native Bridge API**: Handles token exchange and authentication
3. **Fallback Mechanism**: If authentication fails, the app falls back to loading the web app directly

### Code Flow

```swift
loadWebApp() {
    if let userInfo = userInfoStore.getUserInfo(), !userInfo.accessToken.isEmpty {
        authenticateAndLoadWebApp(with: userInfo.accessToken)
    } else {
        loadWebAppDirectly()
    }
}
```

### Error Handling

The integration includes comprehensive error handling:

- **Network Errors**: Fall back to direct loading
- **401 Unauthorized**: Token may be expired (future: trigger refresh)
- **502 Token Exchange Failed**: Invalid or expired token
- **Server Errors**: Log details and fall back to direct loading
- **Invalid Responses**: Graceful degradation to direct loading

## Configuration

### Native Bridge URL

The integration uses the Native Bridge endpoint:

```
https://my.homesteadheritage.org/api/v2/native-bridge.php
```

### Supported Response Types

1. **302 Redirect**: Location header contains authenticated URL
2. **JSON Response**: Contains `redirect` field with authenticated URL

### Timeout

Requests to the Native Bridge have a 30-second timeout to ensure responsiveness.

## Testing Results

### API Functionality ✅

- **Endpoint Accessibility**: The Native Bridge API is accessible and responding
- **Token Validation**: The API properly validates tokens and returns appropriate error responses
- **Error Handling**: Detailed error messages are provided for debugging
- **Response Format**: Both 302 redirects and JSON responses are supported

### Integration Flow ✅

- **Token Detection**: Successfully detects SSO tokens from user store
- **Request Construction**: Properly constructs Native Bridge requests with target URLs
- **Response Processing**: Handles both redirect and JSON response formats
- **Fallback Behavior**: Gracefully falls back to direct loading when authentication fails

### Expected Behavior

1. **With Valid Token**: User gets seamless authentication to web apps
2. **With Invalid/Expired Token**: App falls back to direct loading (user may need to log in manually)
3. **Without Token**: App loads web app directly (user may need to log in manually)

## Debugging and Issue Resolution

### Initial Issue: "Invalid Token" Error

During testing, the Native Bridge API was returning 502 errors with "Invalid token" messages. This was caused by missing OAuth2 scopes required for token exchange.

### Root Cause

The SSO configuration was missing the required scopes for token exchange:

- `urn:ietf:params:oauth:grant-type:token-exchange`
- `urn:ietf:params:oauth:token-type:access_token`

### Solution

Updated `SSOConfig.swift` to include the necessary scopes:

```swift
static let scopes = [
    "openid",
    "profile",
    "email",
    "offline_access",  // For refresh tokens
    "urn:ietf:params:oauth:grant-type:token-exchange",  // For token exchange
    "urn:ietf:params:oauth:token-type:access_token"     // For token exchange
]
```

### Debugging Enhancements

Added comprehensive logging to help diagnose token-related issues:

- Token length and format validation
- JWT payload decoding for debugging
- Detailed error response logging
- Request/response header logging

## Benefits

1. **Seamless Authentication**: Users don't need to log in again when opening web apps
2. **Security**: Uses existing SSO infrastructure and token exchange protocols
3. **Fallback Support**: Works even if authentication fails
4. **Audience-Specific Tokens**: Each web app gets tokens with appropriate audience claims
5. **Robust Error Handling**: Comprehensive error handling ensures the app remains functional

## Future Enhancements

1. **Token Refresh**: Implement automatic token refresh when tokens expire
2. **Caching**: Cache authenticated URLs to reduce API calls
3. **Offline Support**: Better handling of network connectivity issues
4. **Analytics**: Track authentication success/failure rates
5. **User Feedback**: Show loading states and authentication status to users

## Testing

To test the integration:

1. Ensure the user has completed SSO authentication
2. Open a web app from the Signal app
3. Check logs for Native Bridge API calls
4. Verify the web app loads with authentication

### Test Commands

```bash
# Test the integration flow
python3 test_webapp_integration.py

# Test API functionality
python3 test_native_bridge_integration.py
```

## Logging

The integration includes comprehensive logging:

- Native Bridge URL construction
- Request/response details
- Error conditions and fallback decisions
- Authentication success/failure

All logs are prefixed with "WebApp:" for easy filtering.

## Implementation Status

✅ **COMPLETE** - The Native Bridge integration is fully implemented and ready for use.

### What's Working

- Token detection and validation
- Native Bridge API integration
- Comprehensive error handling
- Fallback mechanisms
- Detailed logging for debugging
- **Fixed**: Token exchange scopes configuration

### Ready for Production

The integration is production-ready and will provide seamless authentication for users who have completed SSO login, while gracefully handling cases where authentication is not available.

## Troubleshooting

### Common Issues

1. **502 Token Exchange Failed**: Usually indicates missing scopes or invalid token format
2. **401 Unauthorized**: Token may be expired or invalid
3. **403 Forbidden**: API access restrictions or missing debug keys

### Debug Steps

1. Check SSO configuration scopes
2. Verify token format and validity
3. Review Native Bridge API logs
4. Test with debug endpoints
5. Check client configuration in Keycloak
