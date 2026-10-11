import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../network/api_client.dart';
import 'token_store.dart';
import '../push/charak_push.dart';
import '../crash/charak_crash.dart';

/// The *Web* OAuth client id. Google mints the ID token for this audience, and
/// the backend only accepts tokens for it (GOOGLE_CLIENT_IDS).
const String _kGoogleServerClientId =
    String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

class AuthState {
  final String? token;
  final Map<String, dynamic>? user;
  final bool isLoading;

  const AuthState({this.token, this.user, this.isLoading = false});

  bool get isAuthenticated => token != null;
  bool get hasProfile => user?['name'] != null && (user!['name'] as String).isNotEmpty;
  String? get email => user?['email'] as String?;

  AuthState copyWith({String? token, Map<String, dynamic>? user, bool? isLoading}) =>
      AuthState(
        token: token ?? this.token,
        user: user ?? this.user,
        isLoading: isLoading ?? this.isLoading,
      );
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(const AuthState()) {
    _load();
  }

  final _api = ApiClient.instance;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final token = await TokenStore.instance.read();
    final name  = prefs.getString('user_name');
    final id    = prefs.getString('user_id');
    if (token != null) {
      state = AuthState(token: token, user: id != null ? {'id': id, 'name': name} : null);
      CharakCrash.setUser(id);
      // A returning session still needs its FCM token registered — the token
      // rotates between launches, and the backend only knows the last one it
      // was told about.
      CharakPush.instance.start();
    }
  }

  Future<void> sendOtp(String phone, String role) async {
    await _api.post('/auth/send-otp', {'phone': phone, 'role': role});
  }

  /// Returns true if the user is new (no name set yet).
  Future<bool> verifyOtp(String phone, String code, String role) async {
    final res = await _api.post('/auth/verify-otp', {'phone': phone, 'code': code, 'role': role}) as Map<String, dynamic>;
    return _establish(res);
  }

  bool _googleReady = false;

  /// Sign in with Google, via Firebase Auth.
  ///
  /// google_sign_in still drives the native account picker — Firebase has no
  /// UI of its own for it — but the token that reaches the backend is a
  /// Firebase ID token (POST /auth/firebase), not the raw Google one
  /// (POST /auth/google, which stays live server-side as a fallback but is no
  /// longer called from here). This is the same token shape the website's
  /// Google sign-in and, later, this app's own phone sign-in produce, so the
  /// backend verifies all three the same way.
  ///
  /// Returns whether the profile step (name + phone) is still owed, or null
  /// if the person closed the account picker.
  Future<bool?> signInWithGoogle(String role) async {
    if (_kGoogleServerClientId.isEmpty) {
      throw const ApiException(
          'Google sign-in is not set up in this build (GOOGLE_SERVER_CLIENT_ID).', 0);
    }
    final google = GoogleSignIn.instance;
    if (!_googleReady) {
      await google.initialize(serverClientId: _kGoogleServerClientId);
      _googleReady = true;
    }
    final GoogleSignInAccount account;
    try {
      account = await google.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      throw ApiException('Google sign-in failed. Please try again.', 0);
    }
    final googleIdToken = account.authentication.idToken;
    if (googleIdToken == null) {
      throw const ApiException('Google sign-in failed. Please try again.', 0);
    }

    final fb.UserCredential firebaseCred;
    try {
      firebaseCred = await fb.FirebaseAuth.instance.signInWithCredential(
        fb.GoogleAuthProvider.credential(idToken: googleIdToken),
      );
    } on fb.FirebaseAuthException {
      throw const ApiException('Google sign-in failed. Please try again.', 0);
    }
    final firebaseIdToken = await firebaseCred.user?.getIdToken();
    if (firebaseIdToken == null) {
      throw const ApiException('Google sign-in failed. Please try again.', 0);
    }

    final res = await _api.post('/auth/firebase', {'id_token': firebaseIdToken, 'role': role})
        as Map<String, dynamic>;
    return _establish(res);
  }

  /// Store the session from any login response and say whether the profile
  /// step is still owed.
  Future<bool> _establish(Map<String, dynamic> res) async {
    final prefs = await SharedPreferences.getInstance();
    await TokenStore.instance.write(res['token'] as String);
    final userMap = res['user'] as Map<String, dynamic>;
    await prefs.setString('user_id', userMap['id'] as String);
    if (userMap['name'] != null) {
      await prefs.setString('user_name', userMap['name'] as String);
    }
    state = AuthState(token: res['token'] as String, user: userMap);
    CharakCrash.setUser(userMap['id'] as String?);
    // Registration is authenticated, so it can only happen once the token is
    // stored — not at app start.
    CharakPush.instance.start();
    return res['is_new'] as bool? ?? false;
  }

  /// Patient profile step. [phone] is E.164 and, after Google sign-in, not
  /// OTP-verified.
  Future<void> updateProfile({required String name, String? phone}) async {
    await _api.patch('/users/me', {'name': name, if (phone != null) 'phone': phone});
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_name', name);
    state = state.copyWith(user: {
      ...?state.user, 'name': name, if (phone != null) 'phone': phone,
    });
  }

  /// Delete the patient's own account (self-serve erasure).
  ///
  /// The backend soft-deletes and schedules the personal-data purge; locally we
  /// tear the session down exactly like a logout so the app returns to sign-in.
  /// Password-less login to a seeded demo account for app-store review.
  /// Backed by POST /auth/demo-login, which only works where the server has
  /// DEMO_LOGIN_ENABLED set. Returns true on success.
  Future<bool> demoLogin(String role) async {
    final res = await _api.post('/auth/demo-login', {'role': role})
        as Map<String, dynamic>;
    await _establish(res);
    return true;
  }

  Future<void> deleteAccount() async {
    await _api.delete('/users/me');
    await _teardownSession();
  }

  /// File a doctor account-deletion request. The backend locks the account and
  /// ops completes the erasure; locally we end the session.
  Future<void> requestDoctorDeletion() async {
    await _api.delete('/doctors/me');
    await _teardownSession();
  }

  Future<void> _teardownSession() async {
    CharakCrash.setUser(null);
    await CharakPush.instance.stop();
    // So the next sign-in offers the account picker instead of silently
    // reusing the last Google account. Harmless if Google was never used.
    if (_googleReady) {
      try { await GoogleSignIn.instance.signOut(); } catch (_) {}
    }
    // The backend session (TokenStore) is this app's real session — signing
    // out of Firebase on top just avoids a stale Firebase user lingering
    // on-device after the person has explicitly signed out.
    try { await fb.FirebaseAuth.instance.signOut(); } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await TokenStore.instance.clear();
    await prefs.remove('user_id');
    await prefs.remove('user_name');
    state = const AuthState();
  }

  Future<void> logout() async {
    // Before the token goes: an unregistered device keeps receiving the
    // previous user's booking and payment notifications.
    await _teardownSession();
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (_) => AuthNotifier(),
);
