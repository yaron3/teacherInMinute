# MVVM Architecture Violations Audit

## Summary
Found 8 Views with direct service calls that violate MVVM separation of concerns.

## Critical Violations (Views with ViewModels)

### ChatSessionView
- **Line 787**: `StorageService.shared.uploadBoardSnapshot()`
- **Line 788-789**: `ChatSessionService()` instantiation + `sendImage()`
- **Fix**: Add `sendBoardSnapshot()` method to ChatSessionViewModel

### ProfileView  
- **Line 477**: `PermissionService.shared.requestCapturePermission(for: .camera)`
- **Fix**: Add `requestCameraPermission()` method to ProfileViewModel

### TeacherDocumentsView
- **Line 184**: `PermissionService.shared.requestCapturePermission(for: .camera)`
- **Fix**: Add `requestCameraPermission()` method to TeacherDocumentsViewModel

### TeacherIdentityVerificationView
- **Line 222**: `PermissionService.shared.requestCapturePermission(for: .camera)`
- **Fix**: Add `requestCameraPermission()` method to TeacherIdentityVerificationViewModel

### AskTeacherSheet  
- **Line 658**: `PermissionService.shared.requestCapturePermission(for: .camera)`
- **Fix**: Add `requestAndroidCameraPermission()` method to StudentHomeViewModeling

## Secondary Violations (Presentational Components)

### NotificationPermissionExplainerView
- **Line 79**: `PermissionService.shared.requestNotifications()`
- **Pattern**: Presentational component handling its own permission logic
- **Fix**: Accept `requestPermission` callback from parent ViewModel

### PhotoSourcePicker
- **Lines 96, 159**: `PermissionService.shared.requestCapturePermission()`
- **Pattern**: Reusable component used by multiple Views
- **Fix**: Accept `requestCameraPermission` callback from parent

### RateSessionView
- **Line 249**: `FunctionsService.shared.rateTeacher()`
- **Pattern**: View directly calling API service
- **Fix**: Add RateSessionViewModel or accept `submitRating` callback

## Architecture Principles Violated
1. **Separation of Concerns**: Service calls in Views instead of ViewModels
2. **Testability**: Views with service dependencies are harder to unit test
3. **Reusability**: Views tightly coupled to specific services
4. **Maintainability**: Service logic scattered across multiple Views

## Remediation Strategy
1. **Phase 1** (Done): StudentHomeView, TeacherDashboardView, AskTeacherSheet basic fixes
2. **Phase 2** (Current): Permission methods in ViewModels
3. **Phase 3**: Presentational component callbacks
4. **Phase 4**: Complete API service isolation

