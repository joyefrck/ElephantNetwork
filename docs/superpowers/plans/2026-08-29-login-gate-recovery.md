# ElephantRoute Login Gate Recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make unauthenticated startup open a light login screen immediately and remove the post-login deadlock between managed-profile validation and core startup.

**Architecture:** Separate account authentication from managed subscription reconciliation. The coordinator establishes the secure session first; `GlobalState` starts `FlClashCore`, then explicitly asks the coordinator to download and validate the managed profile. Entry-only widgets receive a fixed light Aurora theme while the authenticated FlClash UI keeps its existing system-driven theme.

**Tech Stack:** Flutter, Riverpod, Dio, Flutter Intl, macOS Flutter release build, Dart unit/widget tests.

---

### Task 1: Lock the deadlock into failing coordinator tests

**Files:**
- Modify: `test/features/account/xboard_account_test.dart`

- [ ] **Step 1: Write a test proving authentication must not wait for profile validation**

Add a test that uses a valid fake login/account response and a blocking `XboardManagedProfileGateway`. The login Future must complete while `gateway.started.isCompleted` remains false:

```dart
test('login completes before managed profile reconciliation', () async {
  final gateway = _BlockingManagedProfileGateway();
  addTearDown(() {
    if (!gateway.release.isCompleted) gateway.release.complete();
  });
  final coordinator = XboardSessionCoordinator(
    api: XboardApi(transport: _FakeTransport({
      XboardConfig.loginPath: {
        'status': 'success',
        'data': {'auth_data': 'token'},
      },
      XboardConfig.userInfoPath: {
        'data': {'email': 'owner@example.com'},
      },
      XboardConfig.subscribeInfoPath: {
        'data': {'subscribe_url': 'https://example.com/sub?token=profile'},
      },
    })),
    store: XboardSessionStore(
      secureStore: _MemorySecureStore(),
      legacyStore: _MemoryLegacyStore(null),
    ),
    managedProfile: gateway,
  );

  expect(
    await coordinator.login('owner@example.com', 'password')
        .timeout(const Duration(milliseconds: 200)),
    isTrue,
  );
  expect(coordinator.state.isAuthenticated, isTrue);
  expect(gateway.started.isCompleted, isFalse);
});
```

- [ ] **Step 2: Write tests for explicit profile synchronization**

Add tests that call `syncManagedProfile()` after login and verify that it invokes the gateway, and that a throwing gateway returns false while `state.isAuthenticated` remains true.

- [ ] **Step 3: Run the focused test and verify RED**

Run:

```bash
flutter test test/features/account/xboard_account_test.dart
```

Expected: the first test times out on current code and the sync tests do not compile because `syncManagedProfile` does not exist.

### Task 2: Split authentication from managed-profile synchronization

**Files:**
- Modify: `lib/features/account/xboard_session_coordinator.dart`
- Modify: `lib/providers/account.dart`
- Modify: `lib/state.dart`
- Test: `test/features/account/xboard_account_test.dart`

- [ ] **Step 1: Make `_activate` establish only the account session**

After `_api.account(token)` and optional secure persistence, set `XboardSessionState.authenticated`. Do not fetch the subscription or call `_managedProfile.reconcile` inside `_activate`.

- [ ] **Step 2: Add the explicit synchronization operation**

Implement this coordinator boundary:

```dart
Future<bool> syncManagedProfile() => _serialized(_syncManagedProfile);

Future<bool> _syncManagedProfile() async {
  final session = state.session;
  if (session == null) return false;
  try {
    final subscription = await _api.managedSubscription(session.token);
    await _managedProfile.reconcile(subscription, session.account);
    _setState(XboardSessionState.authenticated(session));
    return true;
  } catch (error) {
    _setState(XboardSessionState.authenticated(session, error: error));
    return false;
  }
}
```

Expose the same method from `XboardSessionController`.

- [ ] **Step 3: Move synchronization after core startup**

In `GlobalState.startAuthenticatedRuntime`, preserve the order:

```dart
await LegacyUpgradeCleaner.run();
await container.read(coreActionProvider.notifier).startCore();
if (!_didCrashOnPreviousExecution) {
  await container.read(setupActionProvider.notifier).initStatus();
}
final profileReady = await container
    .read(xboardSessionControllerProvider.notifier)
    .syncManagedProfile();
await container.read(profilesActionProvider.notifier).autoUpdateProfiles();
container.read(initProvider.notifier).value = true;
if (!profileReady) {
  showNotifier(currentAppLocalizations.managedSubscriptionUnavailable);
}
```

Synchronization errors are absorbed by the coordinator and must not trigger logout.

- [ ] **Step 4: Run the focused test and verify GREEN**

Run:

```bash
flutter test test/features/account/xboard_account_test.dart
```

Expected: all account, storage, resolver, login-order, and sync tests pass.

- [ ] **Step 5: Commit the flow fix**

```bash
git add lib/features/account/xboard_session_coordinator.dart lib/providers/account.dart lib/state.dart test/features/account/xboard_account_test.dart
git commit -m "fix: start core before managed profile sync"
```

### Task 3: Build the fixed light Aurora login entry

**Files:**
- Create: `lib/features/account/views/xboard_entry_shell.dart`
- Modify: `lib/features/account/views/xboard_gate.dart`
- Modify: `lib/features/account/account.dart`
- Modify: `arb/intl_en.arb`
- Modify: `arb/intl_zh_CN.arb`
- Modify: `arb/intl_ja.arb`
- Modify: `arb/intl_ru.arb`
- Regenerate: `lib/l10n/l10n.dart`
- Regenerate: `lib/l10n/intl/messages_*.dart`
- Create: `test/features/account/xboard_gate_test.dart`

- [ ] **Step 1: Write widget tests against a dark parent theme**

Override `xboardSessionControllerProvider` with a test controller and pump `XboardGate` under `ThemeData.dark()`. Cover `loading`, `unauthenticated`, `authenticating`, and `unavailable`; each must find the login form and a descendant `Theme` whose brightness is light. Authenticated state must render the supplied child without the entry theme.

- [ ] **Step 2: Verify the widget tests fail**

Run:

```bash
flutter test test/features/account/xboard_gate_test.dart
```

Expected: loading and unavailable show their old standalone pages, and the login page inherits dark brightness.

- [ ] **Step 3: Implement `XboardEntryShell`**

Create a focused shell using `ThemeData.light`, a seeded green `ColorScheme`, a `#F6F8F5` background, two non-interactive pale green/blue radial decorations, and a centered white card capped at 420 logical pixels. Keep routine input and button text at 14 logical pixels and the primary button at least 44 logical pixels high.

- [ ] **Step 4: Route all unauthenticated statuses through the login view**

Change `XboardGate` so only `authenticated` renders `child`; all other statuses render `XboardLoginView`. The view receives status-derived busy/loading/error presentation, but remains the same screen instead of switching to `_GateLoadingView` or `_UnavailableView`.

- [ ] **Step 5: Add precise localized errors**

Add these exact values to the four ARB files and regenerate localization output with `dart run intl_utils:generate`:

```json
// arb/intl_en.arb
"invalidCredentials": "Invalid email or password",
"managedSubscriptionUnavailable": "Signed in, but the managed subscription could not be loaded. Please retry later."

// arb/intl_zh_CN.arb
"invalidCredentials": "邮箱或密码错误",
"managedSubscriptionUnavailable": "登录成功，但订阅加载失败，请稍后重试。"

// arb/intl_ja.arb
"invalidCredentials": "メールアドレスまたはパスワードが正しくありません",
"managedSubscriptionUnavailable": "ログインしましたが、管理対象サブスクリプションを読み込めませんでした。しばらくしてから再試行してください。"

// arb/intl_ru.arb
"invalidCredentials": "Неверный адрес электронной почты или пароль",
"managedSubscriptionUnavailable": "Вход выполнен, но не удалось загрузить управляемую подписку. Повторите попытку позже."
```

- [ ] **Step 6: Run widget and account tests**

Run:

```bash
flutter test test/features/account/xboard_gate_test.dart test/features/account/xboard_account_test.dart
```

Expected: all tests pass with no pending timers or overflow exceptions.

- [ ] **Step 7: Commit the entry UI**

```bash
git add arb lib/features/account lib/l10n test/features/account/xboard_gate_test.dart
git commit -m "feat: add light resilient login gate"
```

### Task 4: Full verification and macOS runtime acceptance

**Files:**
- Verify only: all modified source and generated files

- [ ] **Step 1: Run formatting and focused static checks**

```bash
dart format lib/features/account lib/providers/account.dart lib/state.dart test/features/account
git diff --check
flutter analyze --no-fatal-infos
```

Expected: formatting produces no further diff on a second run, diff check emits nothing, and analyze exits 0.

- [ ] **Step 2: Run the complete Flutter suite**

```bash
flutter test
```

Expected: every test passes and the command exits 0.

- [ ] **Step 3: Build the macOS release**

```bash
flutter build macos --release --build-name=2.0.0 --build-number=20000
```

Expected: `build/macos/Build/Products/Release/ElephantRoute.app` exists and `codesign --verify --deep --strict` passes.

- [ ] **Step 4: Install and observe the original interaction**

Quit the currently running test app, copy the verified build to `/Applications/ElephantRoute.app`, launch it, and use Computer Use only to observe that the initial screen is light. The user performs credential entry and submission. Confirm that the button leaves loading, `FlClashCore` starts before managed-profile validation, and no password, email, token, or subscription URL appears in captured logs.

- [ ] **Step 5: Synchronize only after final evidence**

Before pushing, report the exact changed files, test/build results, and remaining unsigned-distribution caveat. Push `main`, confirm local and remote SHA equality, run the packaging workflow, and validate the newly generated DMG as a separate artifact gate.
