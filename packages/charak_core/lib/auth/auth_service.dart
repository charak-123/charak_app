import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../network/api_client.dart';

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
    final token = prefs.getString('auth_token');
    final name  = prefs.getString('user_name');
    final id    = prefs.getString('user_id');
    if (token != null) {
      state = AuthState(token: token, user: id != null ? {'id': id, 'name': name} : null);
    }
  }

  Future<void> sendOtp(String phone, String role) async {
    await _api.post('/auth/send-otp', {'phone': phone, 'role': role});
  }

  /// Returns true if the user is new (no name set yet).
  Future<bool> verifyOtp(String phone, String code, String role) async {
    final res = await _api.post('/auth/verify-otp', {'phone': phone, 'code': code, 'role': role}) as Map<String, dynamic>;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', res['token'] as String);
    final userMap = res['user'] as Map<String, dynamic>;
    await prefs.setString('user_id', userMap['id'] as String);
    if (userMap['name'] != null) {
      await prefs.setString('user_name', userMap['name'] as String);
    }
    state = AuthState(token: res['token'] as String, user: userMap);
    return res['is_new'] as bool? ?? false;
  }

  Future<void> updateName(String name) async {
    await _api.patch('/users/me', {'name': name});
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_name', name);
    state = state.copyWith(user: {...?state.user, 'name': name});
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('user_id');
    await prefs.remove('user_name');
    state = const AuthState();
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (_) => AuthNotifier(),
);
