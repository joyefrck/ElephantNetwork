# Elephant Network FlClash Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a GPLv3 Elephant Network client based on FlClash v0.8.96 for Android, Windows, and macOS with mandatory Xboard login, a managed subscription, native account overview, and authenticated WebView commerce.

**Architecture:** Keep the upstream mihomo Core and platform lifecycle unchanged. Add an isolated `lib/features/xboard/` domain that owns API, secure credentials, session state, managed-profile reconciliation, and portal routes; wire it into the existing Riverpod, Drift, navigation, and application lifecycle boundaries. Preserve the upstream history and regularly merge `upstream/main` into this public fork.

**Tech Stack:** Flutter 3.44.4, Dart 3.12, Riverpod 3, Drift/SQLite, Dio, flutter_secure_storage, webview_flutter, webview_flutter_windows, Go/mihomo, Rust Windows Helper, Android Keystore, macOS Keychain, Windows DPAPI.

---

### Task 1: Fork and compliance baseline

**Files:**
- Modify: `.gitmodules`
- Modify: `README.md`
- Create: `NOTICE`
- Create: `docs/UPSTREAM.md`
- Create: `docs/PRIVACY.md`
- Test: `test/branding_contract_test.dart`

- [ ] **Step 1: Add a failing branding/compliance contract test**

Assert that the app name is `Elephant Network`, the repository points at `joyefrck/ElephantNetwork`, the Clash.Meta submodule uses HTTPS, and GPL/NOTICE files are present.

- [ ] **Step 2: Run the contract test and confirm it fails**

Run: `flutter test test/branding_contract_test.dart`

Expected: FAIL while upstream FlClash constants and SSH submodule URL remain.

- [ ] **Step 3: Establish the fork identity and legal notices**

Keep the upstream `LICENSE`; add `NOTICE` with upstream authorship, Elephant Network modification notice, and source URL. Change the submodule URL to `https://github.com/chen08209/Clash.Meta.git`. Document `origin`/`upstream` synchronization and the requirement to publish source and build scripts beside every binary release.

- [ ] **Step 4: Run the contract test and initialize submodules**

Run:

```bash
git submodule sync --recursive
git submodule update --init --recursive
flutter test test/branding_contract_test.dart
```

Expected: PASS and `core/Clash.Meta` checked out from the `FlClash` branch.

### Task 2: Brand and package identity

**Files:**
- Modify: `lib/common/constant.dart`
- Modify: `pubspec.yaml`
- Modify: Android package files under `android/`
- Modify: macOS identity files under `macos/`
- Modify: Windows runner and packaging files under `windows/`
- Test: `test/platform_identity_contract_test.dart`

- [ ] **Step 1: Write identity assertions**

Assert the production identifiers are `com.elephantroute`, `com.elphantroute.elephantNetwork`, and Windows Inno Setup AppId `{5F1D7A6E-2B3C-4A91-9D74-E0C8F6B1A245}`. Assert build number is greater than `10609`.

- [ ] **Step 2: Run the test and confirm it fails**

Run: `flutter test test/platform_identity_contract_test.dart`

- [ ] **Step 3: Apply Elephant Network identity**

Set version `2.0.0+20000`, package name `com.elephantroute`, app name `Elephant Network`, repository `joyefrck/ElephantNetwork`, and retain the historical macOS bundle id for in-place replacement. Replace upstream icons with the approved transparent ElephantRoute source artwork. Preserve the upstream copyright notice in About/NOTICE.

- [ ] **Step 4: Remove upstream Firebase wiring**

Remove Google Services, Firebase Analytics, and Crashlytics Gradle plugins/dependencies/configuration. Do not add replacement telemetry in this phase.

- [ ] **Step 5: Run the identity contract**

Run: `flutter test test/platform_identity_contract_test.dart`

Expected: PASS.

### Task 3: Xboard domain and secure session

**Files:**
- Create: `lib/features/xboard/models.dart`
- Create: `lib/features/xboard/api.dart`
- Create: `lib/features/xboard/domain_resolver.dart`
- Create: `lib/features/xboard/secure_store.dart`
- Create: `lib/providers/xboard.dart`
- Modify: `lib/providers/providers.dart`
- Test: `test/features/xboard/api_test.dart`
- Test: `test/providers/xboard_session_test.dart`

- [ ] **Step 1: Write API and session failure tests**

Cover login request shape, bearer authorization, user/subscription parsing, `flag=flclash`, safe GET retry after domain failover, no POST retry, secure token restore, 401 logout, and absence of credentials in errors/log strings.

- [ ] **Step 2: Run focused tests and confirm failure**

Run:

```bash
flutter test test/features/xboard/api_test.dart test/providers/xboard_session_test.dart
```

- [ ] **Step 3: Implement the typed API boundary**

Expose:

```dart
abstract interface class XboardApi {
  Future<XboardAuth> login(String email, String password);
  Future<XboardUser> fetchUser();
  Future<XboardSubscription> fetchSubscription();
  Future<Uri> fetchQuickLoginUri(String redirect);
}
```

Use `/api/v1/passport/auth/login`, `/api/v1/user/info`, `/api/v1/user/getSubscribe`, and `/api/v1/passport/auth/getQuickLoginUrl`. Append `flag=flclash` to the subscription URI without changing its token.

- [ ] **Step 4: Implement secure session ownership**

Use `flutter_secure_storage` with platform defaults backed by Keystore, Keychain, and DPAPI. The notifier exposes `restore`, `login`, `refresh`, and `logout`; it stores only the bearer token and normalized last-login email. Logout clears the token before publishing unauthenticated state.

- [ ] **Step 5: Generate Riverpod output and pass tests**

Run:

```bash
dart run build_runner build --delete-conflicting-outputs
flutter test test/features/xboard/api_test.dart test/providers/xboard_session_test.dart
```

Expected: PASS.

### Task 4: Managed Xboard profile

**Files:**
- Modify: `lib/enum/enum.dart`
- Modify: `lib/models/profile.dart`
- Modify: `lib/database/profiles.dart`
- Modify: `lib/database/database.dart`
- Create: `lib/features/xboard/managed_profile.dart`
- Modify: `lib/providers/xboard.dart`
- Test: `test/database/managed_profile_migration_test.dart`
- Test: `test/providers/xboard_managed_profile_test.dart`

- [ ] **Step 1: Write migration and reconciliation tests**

Cover schema v2 to v3 defaults, one managed profile per account, replacement after URL/token rotation, manual-profile preservation, managed-profile removal on logout, and connection stop before removal.

- [ ] **Step 2: Confirm focused tests fail**

Run:

```bash
flutter test test/database/managed_profile_migration_test.dart test/providers/xboard_managed_profile_test.dart
```

- [ ] **Step 3: Add managed-profile metadata**

Add `ProfileSource.user` and `ProfileSource.xboard`, plus nullable `ownerAccountId`. Raise Drift schema to 3 and add non-destructive columns with user-source defaults.

- [ ] **Step 4: Implement reconciliation**

Fetch the subscription, create/update the Xboard profile through the existing `Profile.update()` validation path, select it after login, and refresh on login, resume, and normal profile auto-update. Stop the active listener before deleting the managed profile on logout. Never modify user-created profiles.

- [ ] **Step 5: Generate code and pass tests**

Run:

```bash
dart run build_runner build --delete-conflicting-outputs
flutter test test/database/managed_profile_migration_test.dart test/providers/xboard_managed_profile_test.dart
```

Expected: PASS.

### Task 5: Mandatory login lifecycle

**Files:**
- Create: `lib/features/xboard/session_gate.dart`
- Modify: `lib/application.dart`
- Modify: `lib/state.dart`
- Modify: `lib/manager/app_manager.dart`
- Test: `test/widgets/xboard_session_gate_test.dart`
- Test: `test/providers/xboard_runtime_test.dart`

- [ ] **Step 1: Write lifecycle tests**

Cover loading, login, authenticated application, expired token, and logout. Verify Core startup and auto-run do not occur before authentication and occur exactly once after successful restore/login.

- [ ] **Step 2: Confirm tests fail**

Run:

```bash
flutter test test/widgets/xboard_session_gate_test.dart test/providers/xboard_runtime_test.dart
```

- [ ] **Step 3: Gate authenticated runtime initialization**

Split global attach into shell initialization and idempotent authenticated Core initialization. Restore the secure session before Core start; render the login view until authenticated. On logout, stop the listener and return to the login surface without terminating the reusable Core facade.

- [ ] **Step 4: Pass lifecycle tests**

Run the focused command from Step 2 and expect PASS.

### Task 6: Account overview and localized navigation

**Files:**
- Create: `lib/views/account/login.dart`
- Create: `lib/views/account/account.dart`
- Create: `lib/views/account/account_metric.dart`
- Modify: `lib/views/views.dart`
- Modify: `lib/common/navigation.dart`
- Modify: `lib/enum/enum.dart`
- Modify: `arb/intl_en.arb`
- Modify: `arb/intl_zh_CN.arb`
- Modify: `arb/intl_ja.arb`
- Modify: `arb/intl_ru.arb`
- Test: `test/widgets/xboard_login_test.dart`
- Test: `test/widgets/xboard_account_test.dart`

- [ ] **Step 1: Write widget tests**

Cover validation, loading, API error, password obscuring, account values, missing plan, long-term expiry, refresh, logout, and navigation taps.

- [ ] **Step 2: Confirm widget tests fail**

Run:

```bash
flutter test test/widgets/xboard_login_test.dart test/widgets/xboard_account_test.dart
```

- [ ] **Step 3: Implement Material You account surfaces**

Keep routine text at 14 logical pixels, metric labels at 14, values at 16 with strong weight, controls at least 36 high, and the approved transparent ElephantRoute artwork. Add Account to mobile/desktop navigation without replacing existing FlClash pages.

- [ ] **Step 4: Generate localization and pass tests**

Run:

```bash
dart run intl_utils:generate
flutter test test/widgets/xboard_login_test.dart test/widgets/xboard_account_test.dart
```

Expected: PASS with no hardcoded new Chinese UI strings in `lib/`.

### Task 7: Authenticated commerce WebView

**Files:**
- Create: `lib/features/xboard/portal.dart`
- Create: `lib/widgets/xboard_webview.dart`
- Modify: `lib/views/account/account.dart`
- Modify: `pubspec.yaml`
- Test: `test/features/xboard/portal_test.dart`
- Test: `test/widgets/xboard_webview_test.dart`

- [ ] **Step 1: Write portal and navigation-policy tests**

Cover `plan`, `order`, and `ticket` redirects; approved-host navigation; external-link handoff; blocked unsupported schemes; popups; permission denial; token/URL redaction; WebView2-missing browser fallback; and cookie cleanup on logout.

- [ ] **Step 2: Confirm tests fail**

Run:

```bash
flutter test test/features/xboard/portal_test.dart test/widgets/xboard_webview_test.dart
```

- [ ] **Step 3: Implement the cross-platform portal**

Use `webview_flutter` for Android/macOS and `webview_flutter_windows` for Windows. Load only the server-generated quick-login URI, deny WebView permission requests, keep approved Xboard hosts in-app, send external payment apps/links to the OS, and expose a browser fallback.

- [ ] **Step 4: Pass focused tests**

Run the Step 2 command and expect PASS.

### Task 8: Elephant Network updates

**Files:**
- Create: `lib/features/xboard/update.dart`
- Modify: `lib/providers/actions/common.dart`
- Modify: `lib/common/constant.dart`
- Test: `test/features/xboard/update_test.dart`

- [ ] **Step 1: Write update-contract tests**

Cover platform/app key, semantic version comparison, SHA-256 requirement, no-update, forced update, malformed response, and download URL resolution. Assert no request targets the upstream GitHub release API.

- [ ] **Step 2: Implement the existing distribution API adapter**

Call `/api/v1/app/update` with app key, platform, channel, version, build, architecture, and installation id. Present release notes using the existing update dialog and open the distribution artifact URL.

- [ ] **Step 3: Pass tests**

Run: `flutter test test/features/xboard/update_test.dart`

Expected: PASS.

### Task 9: In-place upgrade cleanup

**Files:**
- Modify: `windows/packaging/exe/inno_setup.iss`
- Modify: `macos/Runner/AppDelegate.swift`
- Modify: Android application startup under `android/app/`
- Create: `docs/UPGRADE.md`
- Test: `test/legacy_upgrade_contract_test.dart`

- [ ] **Step 1: Write legacy-cleanup contract tests**

Assert Windows stops/removes `ElephantNetworkService` and old sing-box, restores only the owned `127.0.0.1:2334` proxy, and retains the Inno AppId. Assert macOS removes the old LaunchDaemon/Helper before new runtime startup. Assert Android keeps the legacy package id and migrates/deletes the legacy plaintext token.

- [ ] **Step 2: Implement platform cleanup before new runtime ownership**

Keep cleanup platform-scoped and idempotent. Do not add a second Core lifecycle owner: installers/native startup clean legacy artifacts, while normal FlClash Core start/stop remains in existing owners.

- [ ] **Step 3: Run portable contracts**

Run: `flutter test test/legacy_upgrade_contract_test.dart`

Expected: PASS. Record that Windows SCM and real macOS LaunchDaemon behavior still require their host acceptance runs.

### Task 10: Legacy Xboard archive and release gates

**Files:**
- Modify in Xboard: `clients/README.md`
- Create in Xboard: `clients/elephant-route-deprecated/ARCHIVED.md`
- Create: `docs/RELEASE.md`

- [ ] **Step 1: Mark the old client read-only**

State that `clients/elephant-route-deprecated` is retained only for historical releases and migration evidence, and direct all new client work to `https://github.com/joyefrck/ElephantNetwork`.

- [ ] **Step 2: Run complete Dart/Flutter checks**

Run:

```bash
flutter pub get
flutter analyze --no-fatal-infos
flutter test --reporter expanded
```

- [ ] **Step 3: Run bundled package and native portable checks**

Run the local plugin analyses/tests, build-tool tests, `CGO_ENABLED=0 go test .`, `CGO_ENABLED=0 go vet .`, Cargo format/tests, and Android Kotlin compilation documented in `.agents/commands.md`.

- [ ] **Step 4: Build supported host artifacts**

Build macOS arm64 and Android arm64 locally. Dispatch Windows x64 build and upgrade acceptance to CI. Record host/device gaps without treating portable tests as platform acceptance.

- [ ] **Step 5: Verify Android signing before public replacement**

Obtain the currently distributed 1.6.9 APK, compare its signer certificate with the available signing key, and block replacement publication on mismatch. Publish binary, SHA-256, source tag, NOTICE, LICENSE, and build instructions together.
