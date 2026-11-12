import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'drive_client.dart';
import 'library_sync.dart';
import 'sync_engine.dart';
import 'sync_merge.dart';

/// The Web application OAuth client from Google Cloud Console. Android
/// sign-in asks for it; it isn't a secret. Empty until it's set up.
const googleWebClientId =
    '247000065425-rmq3u564igskk345ncdgu2uljscj4lj1.apps.googleusercontent.com';

/// Signs in to Google and hands out tokens for Scry's Drive folder.
abstract class DriveAuth {
  /// A token for the app data folder, or null when signing in needs the
  /// person (only tried when [interactive]).
  Future<String?> token({bool interactive = false});

  /// The token was refused; the next [token] gets a fresh one.
  Future<void> forget(String token);

  String? get email;

  Future<void> signOut();
}

class GoogleDriveAuth implements DriveAuth {
  GoogleDriveAuth(this.clientId);

  final String clientId;

  static const scopes = ['https://www.googleapis.com/auth/drive.appdata'];

  Future<void>? _ready;
  GoogleSignInAccount? _account;

  @override
  String? get email => _account?.email;

  Future<GoogleSignInAccount?> _signIn(bool interactive) async {
    final google = GoogleSignIn.instance;
    await (_ready ??= google.initialize(serverClientId: clientId));
    _account ??=
        await (google.attemptLightweightAuthentication() ??
            Future<GoogleSignInAccount?>.value());
    if (_account == null && interactive) {
      _account = await google.authenticate(scopeHint: scopes);
    }
    return _account;
  }

  @override
  Future<String?> token({bool interactive = false}) async {
    final account = await _signIn(interactive);
    if (account == null) return null;
    final client = account.authorizationClient;
    final auth =
        await client.authorizationForScopes(scopes) ??
        (interactive ? await client.authorizeScopes(scopes) : null);
    return auth?.accessToken;
  }

  @override
  Future<void> forget(String token) async {
    await _account?.authorizationClient.clearAuthorizationToken(
      accessToken: token,
    );
  }

  @override
  Future<void> signOut() async {
    await _ready;
    await GoogleSignIn.instance.signOut();
    _account = null;
  }
}

/// Keeps this device's library in step with the copy in Google Drive: when
/// the app opens or comes back, a little while after something changes,
/// and when it's put away.
class DriveSync extends ChangeNotifier with WidgetsBindingObserver {
  DriveSync(
    this._prefs,
    this._library, {
    DriveAuth? auth,
    RemoteStore Function(String token)? store,
    this.onChanged,
    this.clientId = googleWebClientId,
  }) : _auth = auth ?? GoogleDriveAuth(clientId),
       _store = store ?? DriveClient.new {
    _engine = SyncEngine(_library, loadBase: _loadBase, saveBase: _saveBase);
  }

  static const _kEnabled = 'driveSync.enabled';
  static const _kEmail = 'driveSync.email';
  static const _kLast = 'driveSync.last';
  static const _kBase = 'driveSync.base';

  /// How long after a change before syncing, and the most a run of
  /// changes can put it off.
  static const quiet = Duration(seconds: 20);
  static const longest = Duration(minutes: 2);

  final SharedPreferences _prefs;
  final LibrarySync _library;
  final DriveAuth _auth;
  final RemoteStore Function(String token) _store;
  final String clientId;
  late final SyncEngine _engine;

  /// Called after a sync changed this device, so the lists reload.
  Future<void> Function(SyncOutcome outcome)? onChanged;

  /// Google Cloud has been set up for this build.
  bool get available => clientId.isNotEmpty;

  bool get enabled => available && (_prefs.getBool(_kEnabled) ?? false);
  String? get email => _prefs.getString(_kEmail);

  DateTime? get lastSync {
    final ms = _prefs.getInt(_kLast);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  bool _syncing = false;
  bool get syncing => _syncing;

  String? _error;

  /// Why the last sync failed, for Settings.
  String? get error => _error;

  /// Signing in again is needed (from Settings).
  bool _needsSignIn = false;
  bool get needsSignIn => _needsSignIn;

  bool _again = false;
  bool _applying = false;
  Timer? _timer;
  DateTime? _firstChange;
  bool _disposed = false;

  /// Starts watching the app's comings and goings, and syncs once.
  void start() {
    WidgetsBinding.instance.addObserver(this);
    if (enabled) unawaited(sync());
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!enabled) return;
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(sync());
      case AppLifecycleState.paused:
        // Put away: send what changed now, before the other device opens.
        if (_timer != null) unawaited(sync());
      default:
    }
  }

  /// Something in the library changed here; sync once things settle.
  void changed() {
    if (!enabled || _applying) return;
    final now = DateTime.now();
    _firstChange ??= now;
    final wait = _firstChange!.add(longest).difference(now);
    _timer?.cancel();
    _timer = Timer(wait < quiet ? wait : quiet, () => unawaited(sync()));
  }

  /// Turns sync on, signing in to Google. Returns false if signing in
  /// didn't finish.
  Future<bool> enable() async {
    if (!available) return false;
    _error = null;
    try {
      final token = await _auth.token(interactive: true);
      if (token == null) return false;
    } on GoogleSignInException catch (e) {
      if (e.code != GoogleSignInExceptionCode.canceled) {
        _error = e.description ?? 'Google sign-in failed';
        notifyListeners();
      }
      return false;
    }
    await _prefs.setBool(_kEnabled, true);
    final email = _auth.email;
    if (email != null) await _prefs.setString(_kEmail, email);
    _needsSignIn = false;
    notifyListeners();
    await sync();
    return true;
  }

  /// Turns sync off. What's here and in Drive stays; turning it on again
  /// joins the two, removing nothing.
  Future<void> disable() async {
    _timer?.cancel();
    _timer = null;
    await _prefs.setBool(_kEnabled, false);
    await _prefs.remove(_kBase);
    await _prefs.remove(_kEmail);
    await _prefs.remove(_kLast);
    _error = null;
    _needsSignIn = false;
    try {
      await _auth.signOut();
    } on Exception {
      // Signed out already.
    }
    notifyListeners();
  }

  /// Syncs now. A sync asked for while one runs follows it.
  Future<void> sync() async {
    if (!enabled) return;
    if (_syncing) {
      _again = true;
      return;
    }
    _timer?.cancel();
    _timer = null;
    _firstChange = null;
    _syncing = true;
    notifyListeners();
    try {
      final outcome = await _run();
      _error = null;
      _needsSignIn = false;
      await _prefs.setInt(_kLast, DateTime.now().millisecondsSinceEpoch);
      if (outcome.any) {
        _applying = true;
        try {
          await onChanged?.call(outcome);
        } finally {
          _applying = false;
        }
      }
    } on DriveAuthException {
      _needsSignIn = true;
      _error = 'Sign in to Google again to keep syncing';
    } on SyncBusyException catch (e) {
      _error = '$e';
    } on Exception catch (e) {
      _error = _describe(e);
    } finally {
      _syncing = false;
      notifyListeners();
    }
    if (_again) {
      _again = false;
      await sync();
    }
  }

  Future<SyncOutcome> _run() async {
    var token = await _auth.token();
    if (token == null) throw const DriveAuthException();
    try {
      return await _engine.run(_store(token));
    } on DriveAuthException {
      // An old token; one fresh try.
      await _auth.forget(token);
      token = await _auth.token();
      if (token == null) rethrow;
      return _engine.run(_store(token));
    }
  }

  static String _describe(Exception e) {
    final text = '$e';
    if (text.contains('SocketException') ||
        text.contains('connection') ||
        text.contains('Failed host lookup')) {
      return "Couldn't reach Google Drive; it tries again later";
    }
    return "Couldn't sync: $text";
  }

  Future<SyncBase> _loadBase() async {
    final raw = _prefs.getString(_kBase);
    if (raw == null) return SyncBase.empty;
    try {
      return SyncBase.fromJson((jsonDecode(raw) as Map).cast());
    } on FormatException {
      return SyncBase.empty;
    }
  }

  Future<void> _saveBase(SyncBase base) =>
      _prefs.setString(_kBase, jsonEncode(base.toJson()));
}
