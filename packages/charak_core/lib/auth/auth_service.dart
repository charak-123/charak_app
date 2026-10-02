import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../network/api_client.dart';
import 'token_store.dart';
import '../push/charak_push.dart';

class AuthState {
  final String? token;
  final Map<String, dynamic>? user;
  final bool isLoading;

  const AuthState({this.token, this.user, this.isLoading = false});

  bool get isAuthenticated => token != null;
  bool get hasProfile => user?['name'] != null && (user!['name'] as String).isNotEmpty;

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
    final prefs = await SharedPreferences.getInstance();
    await TokenStore.instance.write(res['token'] as String);
    final userMap = res['user'] as Map<String, dynamic>;
    await prefs.setString('user_id', userMap['id'] as String);
    if (userMap['name'] != null) {
      await prefs.setString('user_name', userMap['name'] as String);
    }
    state = AuthState(token: res['token'] as String, user: userMap);
    // Registration is authenticated, so it can only happen once the token is
    // stored — not at app start.
    CharakPush.instance.start();
    return res['is_new'] as bool? ?? false;
  }

  Future<void> updateName(String name) async {
    await _api.patch('/users/me', {'name': name});
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_name', name);
    state = state.copyWith(user: {...?state.user, 'name': name});
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
    final prefs = await SharedPreferences.getInstance();
    await TokenStore.instance.write(res['token'] as String);
    final userMap = res['user'] as Map<String, dynamic>;
    await prefs.setString('user_id', userMap['id'] as String);
    if (userMap['name'] != null) {
      await prefs.setString('user_name', userMap['name'] as String);
    }
    state = AuthState(token: res['token'] as String, user: userMap);
    CharakPush.instance.start();
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
    await CharakPush.instance.stop();
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
