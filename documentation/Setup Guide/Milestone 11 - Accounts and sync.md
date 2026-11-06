---
title: "Milestone 11: Accounts and sync"
tags:
  - noctua
  - noctua/guide
  - noctua/milestone
milestone: 11
aliases:
  - Milestone 11
updated: 2026-11-06
---
# Milestone 11: Accounts and sync

Noctua syncs the library, progress, open tabs and settings through its own server. Users can sign in with a username and password or Google, or use it as a guest with nothing synced. The `auth` feature uses every layer, including a real application service, and is the template for every repository that later talks to the server.

1. **`auth/domain/session.dart`** (domain): `Session(userId, kind, server, username, email, displayName)` with `AuthKind` (password, google, anonymous), and `AuthError`/`AuthException` with a user-facing message for each failure. The session is saved to preferences; the token is not.
2. **`auth/data/`** (data):
   - `auth_repository.dart`: `AuthRepository(Dio)`, the sync server's `/api/auth/*` endpoints. Every call returns a record `(Session, String token)` or throws an `AuthException`.
   - `fake_auth_repository.dart`: `FakeAuthRepository implements AuthRepository`. Until the server exists, `authRepositoryProvider` returns it. Its rules make every error state reachable: password `wrongpass`, username `taken`, an email starting `taken@`, and server `offline`.
   - `session_repository.dart`: `SessionRepository`, a repository with a cache whose state is the current `Session` (or null). `save` writes the session to the preferences table and the token to `flutter_secure_storage`; the static `restore` runs in `main()` and its result overrides `initialSessionProvider`.
3. **`auth/application/auth_service.dart`** (application): `AuthService` signs in, registers, links a guest, resets passwords, signs out and deletes the account. Each of these spans the auth server, the session store and, on sign-out, the tabs and preferences, which is what the service layer is for.
4. **`auth/presentation/`** (presentation):
   - `auth_controllers.dart`: `SignInController` (shared by Welcome, Sign in and Register), `ForgotPasswordController`, `ChangePasswordController` and `AccountController`, each an `AsyncNotifier<void>` that runs one service call through `AsyncValue.guard`. `sync_controller.dart` holds the placeholder sync status.
   - Sign-in flow: Welcome, Sign in, Register, Forgot password, and a merge dialog for guests who link an account. These use autofill hints and show the controller's error inline.
   - Account and data: the account page (what syncs, change password, sign out, leave guest mode), Sync (conflicts), Devices, and “Your data on the server” with per-category and full deletion.
5. **Start route:** `NoctuaApp` picks the first screen from the saved state: no session → Welcome; setup not done → Setup; tour not done → Tour; otherwise the library.

To plug in the real server later, return `AuthRepository(ref.watch(dioProvider))` from `authRepositoryProvider`, and give the other features’ repositories (`LibraryRepository`, `TabsRepository`, `WorksRepository`…) method bodies that call it. Add the bearer token with a Dio interceptor rather than in each call. No controller or screen changes. Google sign-in needs an OAuth client tied to each flavor’s application ID (`dev.noctua.noctua` and `dev.noctua.noctua.beta`) and signing-key SHA-1, and the official “G” asset on the button.

## Code walkthrough: milestone 11

**Step 1: the session model (domain).** A Freezed class with derived labels, plus conversion to and from preference rows, so the session can be read before the first frame like any other setting:

```dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'session.freezed.dart';

/// How the user signed in to their Noctua sync account. This is separate from
/// source sign-ins (AO3, SpaceBattles…), which stay on the device.
enum AuthKind {
  password,
  google,

  /// No account: everything stays on this device and nothing syncs.
  anonymous,
}

@freezed
abstract class Session with _$Session {
  const factory Session({
    required String userId,
    required AuthKind kind,

    /// Base URL of the sync server this session belongs to.
    required String server,
    String? username,
    String? email,
    String? displayName,
  }) = _Session;
  const Session._();

  bool get isAnonymous => kind == AuthKind.anonymous;
  bool get syncs => !isAnonymous;

  String get label => switch (kind) {
    AuthKind.anonymous => 'Guest on this device',
    _ => displayName ?? username ?? email ?? 'Noctua account',
  };

  String get methodLabel => switch (kind) {
    AuthKind.password => 'Username and password',
    AuthKind.google => 'Google',
    AuthKind.anonymous => 'No account · nothing syncs',
  };

  Map<String, String> toPrefs() => {
    'auth.userId': userId,
    'auth.kind': kind.name,
    'auth.server': server,
    'auth.username': ?username,
    'auth.email': ?email,
    'auth.displayName': ?displayName,
  };

  static Session? fromPrefs(Map<String, String> p) {
    final id = p['auth.userId'];
    final kind = AuthKind.values.where((k) => k.name == p['auth.kind']).firstOrNull;
    if (id == null || kind == null) return null;
    return Session(
      userId: id,
      kind: kind,
      server: p['auth.server'] ?? defaultServer,
      username: p['auth.username'],
      email: p['auth.email'],
      displayName: p['auth.displayName'],
    );
  }

  static const sessionKeys = ['auth.userId', 'auth.kind', 'auth.server', 'auth.username', 'auth.email', 'auth.displayName'];
}

/// Placeholder default; self-hosters change it on the welcome screen.
const defaultServer = 'https://sync.noctua.example';
```

- `AuthKind.anonymous` is a guest: a real session, so the rest of the app doesn't need a "signed out but using the app" special case, but `syncs` is false.
- `toPrefs` uses null-aware map entries (`'auth.username': ?username`): the key is only added when the value isn't null.
- `fromPrefs` returns null for anything incomplete or unrecognised, which the app treats as signed out.
- The token is deliberately not part of the session; it lives in secure storage (step 3).

Errors are an enum with the user-facing message attached, wrapped in one exception type. `toString` returns the message, so the shared `showSnackbarOnError` can show any app exception without knowing its type:

```dart
enum AuthError {
  invalidCredentials('That username and password don’t match.'),
  usernameTaken('That username is taken. Try another, or sign in.'),
  emailTaken('An account already uses that email. Sign in instead?'),
  weakPassword('Use at least 8 characters.'),
  network('Couldn’t reach the sync server. Check your connection or the server address.'),
  cancelled('Sign-in was cancelled.'),
  unknown('Something went wrong. Try again.');

  const AuthError(this.message);
  final String message;
}

class AuthException implements Exception {
  const AuthException(this.error);
  final AuthError error;

  @override
  String toString() => error.message;
}
```

**Step 2: the auth repository (data).** A concrete class over the shared `Dio`, like [[Milestone 03 - In-app updates|milestone 3]]'s `ReleasesRepository`. Every call returns a record `(Session, String token)`, so a backend only has to produce those two things, and every HTTP failure becomes an `AuthException`:

```dart
/// The sync server's auth API.
///
/// Every call returns the [Session] plus an opaque token, or throws an
/// [AuthException]. The caller stores the token; this class keeps nothing.
/// If you use a hosted backend instead (Supabase, PocketBase, Firebase…),
/// rewrite the method bodies and keep the signatures, and nothing above the
/// data layer changes.
class AuthRepository {
  AuthRepository(this._dio);
  final Dio _dio;

  Future<(Session, String)> _post(String server, String path, Map<String, Object?> body, {AuthKind kind = AuthKind.password}) async {
    try {
      final r = await _dio.post<Map<String, dynamic>>('$server/api/auth/$path', data: body);
      final s = r.data!['session'] as Map<String, dynamic>;
      return (
        Session(
          userId: s['userId'] as String,
          kind: kind,
          server: server,
          username: s['username'] as String?,
          email: s['email'] as String?,
          displayName: s['displayName'] as String?,
        ),
        r.data!['token'] as String,
      );
    } on DioException catch (e) {
      throw _toAuthException(e);
    }
  }

  /// The server answers errors with `{"error": "<code>"}`; codes match [AuthError] names.
  static AuthException _toAuthException(DioException e) {
    if (e.response == null) return const AuthException(AuthError.network);
    final code = (e.response!.data as Map<String, dynamic>?)?['error'];
    return AuthException(AuthError.values.where((a) => a.name == code).firstOrNull ?? AuthError.unknown);
  }

  Future<void> _call(String server, String path, Map<String, Object?> body, {String? token}) async {
    try {
      await _dio.post<void>(
        '$server/api/auth/$path',
        data: body,
        options: Options(headers: {if (token != null) 'Authorization': 'Bearer $token'}),
      );
    } on DioException catch (e) {
      throw _toAuthException(e);
    }
  }

  Future<(Session, String)> signInWithPassword({required String server, required String username, required String password}) =>
      _post(server, 'login', {'username': username, 'password': password});

  Future<(Session, String)> register({required String server, required String username, required String email, required String password}) =>
      _post(server, 'register', {'username': username, 'email': email, 'password': password});

  /// Real version: get a Google ID token on the device (google_sign_in or
  /// Credential Manager), then exchange it with the server for a session.
  Future<(Session, String)> signInWithGoogle({required String server}) => throw const AuthException(AuthError.unknown);

  /// A device-only guest. No server round trip is needed.
  Future<(Session, String)> signInAnonymously() async {
    final rng = Random.secure();
    final token = List.generate(32, (_) => rng.nextInt(16).toRadixString(16)).join();
    return (Session(userId: 'guest_${token.substring(0, 12)}', kind: AuthKind.anonymous, server: 'device'), token);
  }

  /// Turns the current guest into a real account, keeping this device's data.
  Future<(Session, String)> linkWithPassword({
    required String server,
    required String username,
    required String email,
    required String password,
  }) => register(server: server, username: username, email: email, password: password);

  Future<(Session, String)> linkWithGoogle({required String server}) => signInWithGoogle(server: server);

  Future<void> requestPasswordReset({required String server, required String email}) => _call(server, 'reset', {'email': email});

  Future<void> changePassword({required String server, required String token, required String current, required String next}) =>
      _call(server, 'password', {'current': current, 'next': next}, token: token);

  Future<void> signOut({required String server, required String token}) => _call(server, 'logout', {}, token: token);

  Future<void> deleteAccount({required String server, required String token}) => _call(server, 'delete', {}, token: token);
}

/// There is no sync server yet, so the app runs on [FakeAuthRepository]. When
/// the server exists, return `AuthRepository(ref.watch(dioProvider))` here.
@Riverpod(keepAlive: true)
AuthRepository authRepository(Ref ref) => FakeAuthRepository();
```

- `_toAuthException` maps no response to `network`, and the server's `{"error": "<code>"}` body to the `AuthError` of the same name, so the messages the user sees are written once, in the domain.
- If you use a hosted backend (Supabase, PocketBase, Firebase…) instead of your own server, rewrite these method bodies and keep the signatures.
- The provider returns the fake until the server exists. That is the only line to change when it does.

The fake has rules so every error state can be reached by typing something:

```dart
import 'dart:math';

import 'package:noctua/src/features/auth/data/auth_repository.dart';
import 'package:noctua/src/features/auth/domain/session.dart';

/// Demo backend for the prototype, used until the sync server exists, and in
/// tests. Rules, so every error state can be seen:
/// - password `wrongpass` → invalid credentials
/// - username `taken` → username taken; email starting `taken@` → email taken
/// - a server address containing `offline` → network error
/// - anything else succeeds after a short delay
class FakeAuthRepository implements AuthRepository {
  final _rng = Random();

  Future<void> _wait(String? server) async {
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (server != null && server.contains('offline')) throw const AuthException(AuthError.network);
  }

  String _token() => List.generate(32, (_) => _rng.nextInt(16).toRadixString(16)).join();
  String _id() => 'u_${_token().substring(0, 12)}';

  @override
  Future<(Session, String)> signInWithPassword({required String server, required String username, required String password}) async {
    await _wait(server);
    if (password == 'wrongpass') throw const AuthException(AuthError.invalidCredentials);
    final email = username.contains('@') ? username : null;
    return (
      Session(
        userId: _id(),
        kind: AuthKind.password,
        server: server,
        username: email == null ? username : username.split('@').first,
        email: email,
      ),
      _token(),
    );
  }
```

The rest of the fake follows the same shape. Because it `implements AuthRepository`, the compiler checks that it has every public method the real one has.

**Step 3: the session repository (data).** The current session is app state every screen can read synchronously, so it is a repository with a cache, like [[Milestone 04 - Preferences and the local database|milestone 4]]'s preferences. Tokens go to `flutter_secure_storage`, which uses the Android Keystore, never into Drift:

```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:noctua/src/database/app_database.dart';
import 'package:noctua/src/features/auth/domain/session.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'session_repository.g.dart';

/// Restored in main() before the first frame.
@Riverpod(keepAlive: true)
Session? initialSession(Ref ref) => null;

/// The signed-in account (or guest) on this device; null when signed out.
///
/// A repository with a cache: its state is the current session. The session's
/// fields are stored with the preferences in Drift, and the token in the
/// Android Keystore-backed secure storage, never in Drift.
@Riverpod(keepAlive: true)
class SessionRepository extends _$SessionRepository {
  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'auth.token';

  @override
  Session? build() => ref.read(initialSessionProvider);

  /// Reads the saved session before the first frame. A non-guest session
  /// without a token counts as signed out (for example after the app's
  /// storage was cleared).
  static Future<Session?> restore(Map<String, String> prefs) async {
    final session = Session.fromPrefs(prefs);
    if (session == null || session.isAnonymous) return session;
    final token = await _storage.read(key: _tokenKey);
    return token == null ? null : session;
  }

  Future<void> save(Session session, String token) async {
    final db = ref.read(appDatabaseProvider);
    await db.deletePreferences(Session.sessionKeys);
    for (final e in session.toPrefs().entries) {
      await db.putPreference(e.key, e.value);
    }
    await _storage.write(key: _tokenKey, value: token);
    state = session;
  }

  Future<String?> token() => _storage.read(key: _tokenKey);

  /// Forgets the session and its token on this device.
  Future<void> clear() async {
    await _storage.delete(key: _tokenKey);
    await ref.read(appDatabaseProvider).deletePreferences(Session.sessionKeys);
    state = null;
  }
}
```

- `restore` is `static` because it runs in `main()` before any provider exists. A saved non-guest session without a token (the user cleared app storage, or restored a backup to a new phone) is treated as signed out rather than a broken signed-in state.
- `save` writes the session rows to Drift and the token to secure storage, then sets `state`, which is what moves the UI on.
- The repository knows nothing about the server: storing a session and getting one are separate jobs.

**Step 4: the auth service (application).** Signing in means asking the server and then storing the result; signing out means telling the server, forgetting the session, and for guests clearing tabs and settings. Those span four repositories, so they live in a service:

```dart
import 'package:noctua/src/features/auth/data/auth_repository.dart';
import 'package:noctua/src/features/auth/data/session_repository.dart';
import 'package:noctua/src/features/auth/domain/session.dart';
import 'package:noctua/src/features/tabs/data/tabs_repository.dart';
import 'package:noctua/src/preferences/pref.dart';
import 'package:noctua/src/preferences/preferences_repository.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'auth_service.g.dart';

/// Signing in, out and managing the account.
///
/// Each method spans several repositories: the server's [AuthRepository], the
/// [SessionRepository] that stores the result, and, when signing out, the tabs
/// and preferences that are cleared. Controllers call this service; they
/// never talk to those repositories directly. Methods throw [AuthException].
class AuthService {
  AuthService(this.ref);
  final Ref ref;

  AuthRepository get _auth => ref.read(authRepositoryProvider);
  SessionRepository get _session => ref.read(sessionRepositoryProvider.notifier);
  String get _server => ref.read(preferencesRepositoryProvider.notifier).get(Prefs.syncServer);

  Future<void> _store(Future<(Session, String)> call) async {
    final (session, token) = await call;
    await _session.save(session, token);
  }

  Future<void> signInWithPassword({required String username, required String password}) =>
      _store(_auth.signInWithPassword(server: _server, username: username, password: password));

  Future<void> register({required String username, required String email, required String password}) =>
      _store(_auth.register(server: _server, username: username, email: email, password: password));

  Future<void> signInWithGoogle() => _store(_auth.signInWithGoogle(server: _server));

  Future<void> signInAnonymously() => _store(_auth.signInAnonymously());

  Future<void> linkWithPassword({required String username, required String email, required String password}) =>
      _store(_auth.linkWithPassword(server: _server, username: username, email: email, password: password));

  Future<void> linkWithGoogle() => _store(_auth.linkWithGoogle(server: _server));

  Future<void> requestPasswordReset(String email) => _auth.requestPasswordReset(server: _server, email: email);

  Future<void> changePassword({required String current, required String next}) async {
    final token = await _session.token() ?? '';
    await _auth.changePassword(server: _server, token: token, current: current, next: next);
  }

  /// Signs out. [removeLocalData] also clears this device's copy of the tabs
  /// and settings (always true for guests, who have no backup).
  Future<void> signOut({required bool removeLocalData}) async {
    final session = ref.read(sessionRepositoryProvider);
    final token = await _session.token();
    if (token != null && session?.syncs == true) {
      try {
        await _auth.signOut(server: session!.server, token: token);
      } on Object {
        // Signing out locally still succeeds when the server can't be reached.
      }
    }
    await _session.clear();
    if (removeLocalData || session?.isAnonymous == true) {
      ref.read(tabsRepositoryProvider.notifier).closeAll();
      await ref.read(preferencesRepositoryProvider.notifier).resetAll();
    }
  }

  Future<void> deleteAccount() async {
    final token = await _session.token();
    if (token != null) await _auth.deleteAccount(server: _server, token: token);
    await signOut(removeLocalData: true);
  }
}

@riverpod
AuthService authService(Ref ref) => AuthService(ref);
```

- `_store` is the one place a successful call is saved, so every sign-in method is a one-liner.
- `_server` reads the `sync.server` preference on each call, so changing the server on the welcome screen applies to the next attempt.
- `signOut` tells the server, but swallows errors: being offline must never stop someone signing out. Guests always lose local data on sign-out, since there's no account to restore it from.
- Every method throws `AuthException` on failure; the controllers in step 6 turn that into state.

**Step 5: restoring in `main()`.** After preferences load, before `runApp`:

```dart
final session = await SessionRepository.restore(prefs);
// …
initialSessionProvider.overrideWithValue(session),
```

`NoctuaApp`'s `deepLinkBuilder` ([[Milestone 05 - Theming and the app shell|milestone 5]], step 10) now reads `sessionRepositoryProvider`: no session goes to Welcome.

**Step 6: the controllers (presentation).** Each auth screen gets a controller whose state is `AsyncValue<void>`: loading while a call runs, then data (done) or an error. One small mixin does the bookkeeping for all of them:

```dart
import 'package:noctua/src/features/auth/application/auth_service.dart';
import 'package:noctua/src/features/auth/domain/session.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'auth_controllers.g.dart';

/// The message to show for a controller's error, or null when there is none.
String? authErrorMessage(Object? error) => switch (error) {
  null => null,
  AuthException(:final error) => error.message,
  _ => AuthError.unknown.message,
};

/// Runs [call] as the controller's state: loading while it runs, then data or
/// the error. Returns whether it succeeded, so the screen can move on.
mixin _Guard on $AsyncNotifier<void> {
  Future<bool> guard(Future<void> Function() call) async {
    state = const AsyncLoading();
    final result = await AsyncValue.guard(call);
    if (!ref.mounted) return false;
    state = result;
    return !result.hasError;
  }
}

/// Shared by the welcome, sign-in and register screens.
@riverpod
class SignInController extends _$SignInController with _Guard {
  @override
  FutureOr<void> build() {}

  AuthService get _auth => ref.read(authServiceProvider);

  Future<bool> signInWithPassword({required String username, required String password}) =>
      guard(() => _auth.signInWithPassword(username: username, password: password));

  Future<bool> register({required String username, required String email, required String password}) =>
      guard(() => _auth.register(username: username, email: email, password: password));

  Future<bool> signInWithGoogle() => guard(_auth.signInWithGoogle);

  Future<bool> signInAnonymously() => guard(_auth.signInAnonymously);

  Future<bool> linkWithPassword({required String username, required String email, required String password}) =>
      guard(() => _auth.linkWithPassword(username: username, email: email, password: password));

  Future<bool> linkWithGoogle() => guard(_auth.linkWithGoogle);
}

@riverpod
class ForgotPasswordController extends _$ForgotPasswordController with _Guard {
  @override
  FutureOr<void> build() {}

  Future<bool> send(String email) => guard(() => ref.read(authServiceProvider).requestPasswordReset(email));
}

@riverpod
class ChangePasswordController extends _$ChangePasswordController with _Guard {
  @override
  FutureOr<void> build() {}

  Future<bool> save({required String current, required String next}) =>
      guard(() => ref.read(authServiceProvider).changePassword(current: current, next: next));
}

/// Signing out and deleting the account, from the account and server data screens.
@riverpod
class AccountController extends _$AccountController with _Guard {
  @override
  FutureOr<void> build() {}

  Future<bool> signOut({required bool removeLocalData}) =>
      guard(() => ref.read(authServiceProvider).signOut(removeLocalData: removeLocalData));

  Future<bool> deleteAccount() => guard(ref.read(authServiceProvider).deleteAccount);
}
```

- `guard` sets `AsyncLoading`, runs the call through `AsyncValue.guard` (which catches the exception and returns `AsyncError`), and returns whether it worked, so a screen can navigate only on success.
- `ref.mounted` is false if the screen closed while the call was running; setting state on a disposed controller would throw, so the result is dropped.
- The mixin is `on $AsyncNotifier<void>`, the generated base class, so it can use `state` and `ref` like the controller itself.
- Controllers are auto-disposed: leaving a screen throws away its error, so coming back starts clean.
- `authErrorMessage` turns the controller's error into the sentence to show, with a fallback for anything that isn't an `AuthException`.

`sync_controller.dart` holds the account screen's sync status; it is a placeholder (`syncNow` flips `syncing` for 1.5 s) until the server can actually sync.

**Step 7: the shared sign-in flow.** Welcome, Sign in and Register all show the same busy state and error, and do the same thing on success. A mixin on `ConsumerState` reads both from the controller and owns the navigation:

```dart
/// Shared by the welcome, sign-in and register screens: the controller's
/// state as a busy flag and an error message, and where to go after success.
mixin _AuthFlow<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  bool get busy => ref.watch(signInControllerProvider).isLoading;
  String? get error => authErrorMessage(ref.watch(signInControllerProvider).error);

  /// Runs [call] on the controller; on success finishes autofill and either
  /// returns to the account screen (when linking a guest) or opens the library.
  Future<void> attempt(Future<bool> Function(SignInController c) call, {required bool linking, String? done}) async {
    final ok = await call(ref.read(signInControllerProvider.notifier));
    if (!ok || !mounted) return;
    TextInput.finishAutofillContext();
    if (linking) {
      context.router.popUntilRouteWithName(AccountRoute.name);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done ?? 'Account linked. Your library now syncs.')));
    } else {
      // First time on this device: setup, then the tour, then the library.
      context.router.replaceAll([ref.readPref(Prefs.setupDone) ? const HomeShellRoute() : const SetupRoute()]);
    }
  }
}
```

- `busy` and `error` are getters that `ref.watch` the controller, so the page rebuilds when its state changes without any `setState`.
- `attempt` takes a function that receives the controller: screens call `attempt((c) => c.signInWithGoogle(), linking: false)` and never hold the service or a repository.
- `TextInput.finishAutofillContext()` tells Android's autofill (and password managers) that the form succeeded, which is when they offer to save the password.
- After a first sign-in, `replaceAll` swaps the whole stack for setup or the library, so back can't return to the sign-in form. When a guest is linking an account, `popUntilRouteWithName(AccountRoute.name)` returns to the account screen they started from.

**Step 8: the sign-in page.** A `Form` with validators, wrapped in an `AutofillGroup`:

```dart
class SignInPage extends ConsumerStatefulWidget {
  /// [linking]: a guest is turning their device data into an account.
  const SignInPage({super.key, this.linking = false});
  final bool linking;

  @override
  ConsumerState<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends ConsumerState<SignInPage> with _AuthFlow {
  final _form = GlobalKey<FormState>();
  final _user = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _user.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    // Signing a guest into an existing account: ask what to do with this device's data first.
    if (widget.linking) {
      final merge = await showMergeDialog(context);
      if (merge == null) return;
      if (!mounted) return;
      return attempt(
        (c) => c.signInWithPassword(username: _user.text.trim(), password: _password.text),
        linking: true,
        done: merge ? 'Signed in. This device’s library was merged into your account.' : 'Signed in. Showing your account’s library.',
      );
    }
    await attempt((c) => c.signInWithPassword(username: _user.text.trim(), password: _password.text), linking: false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.linking ? 'Sign in to sync' : 'Sign in')),
      body: AuthBody(
        children: [
          if (widget.linking) const _LinkingNote(),
          if (error case final e?) AuthErrorBanner(e),
          Form(
            key: _form,
            child: AutofillGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _user,
                    autofillHints: const [AutofillHints.username, AutofillHints.email],
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    textInputAction: TextInputAction.next,
                    validator: (v) => (v ?? '').trim().isEmpty ? 'Enter your username or email' : null,
                    decoration: const InputDecoration(labelText: 'Username or email', prefixIcon: Icon(Symbols.person_rounded)),
                  ),
                  const SizedBox(height: 16),
                  PasswordField(
                    controller: _password,
                    validator: (v) => (v ?? '').isEmpty ? 'Enter your password' : null,
                    onSubmitted: (_) => _submit(),
                  ),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => context.router.push(ForgotPasswordRoute(email: _user.text.contains('@') ? _user.text.trim() : '')),
              child: const Text('Forgot password?'),
            ),
          ),
          const SizedBox(height: 8),
          BusyButton(label: 'Sign in', busy: busy, onPressed: _submit),
          const OrDivider(),
          GoogleButton(
            onPressed: busy
                ? null
                : () => attempt((c) => widget.linking ? c.linkWithGoogle() : c.signInWithGoogle(), linking: widget.linking),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('New to Noctua?'),
              TextButton(
                onPressed: () => context.router.replace(RegisterRoute(linking: widget.linking)),
                child: const Text('Create account'),
              ),
            ],
          ),
          if (!widget.linking) const ServerChip(),
        ],
      ),
    );
  }
```

- `_form.currentState!.validate()` runs every field's `validator` and shows their messages; the network call only happens when all pass.
- `autofillHints` tell password managers what each field is. `AutofillHints.username` and `.email` together let a saved login fill either form.
- `textInputAction: TextInputAction.next` moves the keyboard's action button to the password field; the password field's `onSubmitted` submits.
- When linking, the merge dialog asks whether this device's library should be merged into the account or replaced by it. `merge == null` (dialog dismissed) cancels.
- `context.router.replace(RegisterRoute(...))` swaps sign-in for register, so back from register doesn't return to sign-in.

The forgot-password page and the change-password dialog use their own controllers the same way: `final state = ref.watch(forgotPasswordControllerProvider)`, then `state.isLoading` for the button and `authErrorMessage(state.error)` for the banner. Change-password maps `invalidCredentials` to "Your current password is wrong." with a pattern in a `switch`, because there the wrong password is the current one.

**Step 9: shared auth widgets.** Small widgets reused by every auth screen live in `presentation/widgets/auth_widgets.dart`. The password field with a visibility toggle and the strength meter:

```dart
class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    this.label = 'Password',
    this.newPassword = false,
    this.validator,
    this.onSubmitted,
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final bool newPassword;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: widget.controller,
    obscureText: _hidden,
    enableSuggestions: false,
    autocorrect: false,
    autofillHints: [widget.newPassword ? AutofillHints.newPassword : AutofillHints.password],
    textInputAction: widget.onSubmitted == null ? TextInputAction.next : TextInputAction.done,
    onFieldSubmitted: widget.onSubmitted,
    onChanged: widget.onChanged,
    validator: widget.validator,
    decoration: InputDecoration(
      labelText: widget.label,
      prefixIcon: const Icon(Symbols.lock_rounded),
      suffixIcon: IconButton(
        tooltip: _hidden ? 'Show password' : 'Hide password',
        icon: Icon(_hidden ? Symbols.visibility_rounded : Symbols.visibility_off_rounded),
        onPressed: () => setState(() => _hidden = !_hidden),
      ),
    ),
  );
}

/// 0–4: length plus character variety. A hint, not a gate.
int passwordStrength(String p) {
  if (p.isEmpty) return 0;
  var score = 0;
  if (p.length >= 8) score++;
  if (p.length >= 12) score++;
  final kinds = [RegExp('[a-z]'), RegExp('[A-Z]'), RegExp('[0-9]'), RegExp(r'[^A-Za-z0-9]')].where((r) => r.hasMatch(p)).length;
  if (kinds >= 2) score++;
  if (kinds >= 3 && p.length >= 10) score++;
  return score;
}
```

And the validators, shared by register and change-password:

```dart
final _usernamePattern = RegExp(r'^[A-Za-z0-9_.-]{3,40}$');
final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

String? validateUsername(String? v) {
  final s = v?.trim() ?? '';
  if (s.isEmpty) return 'Enter a username';
  if (!_usernamePattern.hasMatch(s)) return '3–40 characters: letters, numbers, _ . -';
  return null;
}

String? validateEmail(String? v) {
  final s = v?.trim() ?? '';
  if (s.isEmpty) return 'Enter your email';
  if (!_emailPattern.hasMatch(s)) return 'That doesn’t look like an email address';
  return null;
}

String? validateNewPassword(String? v) => (v ?? '').length < 8 ? AuthError.weakPassword.message : null;
```

`BusyButton` swaps its label for a small spinner and disables itself while `busy`, so a double tap can't send two sign-in requests.

**Step 10: the account screen.** It watches `sessionRepositoryProvider` and `syncControllerProvider` and shows one of two layouts: for guests, a card offering "Create account" or "I already have one", which push the register or sign-in page with `linking: true`; for accounts, the signed-in method, sync status with Sync now, what syncs (five `PrefSwitch`es over the `sync.*` preferences), devices, change password, your data on the server, sign out, and delete account behind a `confirm` dialog.

Sign out and delete go through `AccountController`, and only navigate to Welcome when the controller reports success. If they fail, the screen shows it with the shared snackbar helper, set up once in `build`:

```dart
ref.listen(accountControllerProvider, (_, state) => state.showSnackbarOnError(context));
```

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

extension AsyncValueUI on AsyncValue<void> {
  /// Shows a snackbar when a controller's action failed. Call it from
  /// `ref.listen` in a screen's build, so it runs once per state change.
  void showSnackbarOnError(BuildContext context) {
    if (isLoading || !hasError) return;
    // App exceptions override toString() with a message a user can act on.
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
  }
}
```

`ref.listen` runs its callback once per state change rather than on every rebuild, which is what a snackbar needs.

> [!success] Checkpoint
> clear app data. The app opens on Welcome; “Continue without an account” makes a guest, and signing in with password `wrongpass` shows the inline error.

![[noctua-m11-accounts.png]]
*Milestone 11: Welcome, Sign in and Account*

---
← [[Milestone 10 - Settings]] · [[00 Index|Index]] · [[Milestone 12 - Onboarding]] →
