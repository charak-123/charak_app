import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Secure storage for the session JWT.
///
/// The JWT is the sole bearer credential for the patient and doctor apps and is
/// valid for 30 days with no server-side revocation, so it must never sit in
/// plaintext `SharedPreferences` (readable on a rooted/jailbroken device or via
/// a device/cloud backup). It lives in the platform keystore/keychain instead:
/// Android EncryptedSharedPreferences (AES), iOS Keychain.
///
/// Non-sensitive profile hints (user id, display name) stay in SharedPreferences
/// — they are not credentials.
class TokenStore {
  TokenStore._();
  static final TokenStore instance = TokenStore._();

  static const _key = 'auth_token';

  // In-memory cache so the platform keystore/keychain is read once per launch
  // rather than on every API request (a secure-storage read is a platform
  // channel round-trip). `_loaded` distinguishes "not yet read" from "read, no
  // token". Cleared on write/clear so it never goes stale.
  String? _cached;
  bool _loaded = false;

  // `first_unlock` keeps the Keychain item readable in the background after the
  // first post-boot unlock, which a push-driven app needs, without the
  // this-device-only loosening of its weaker variants.
  final FlutterSecureStorage _secure = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  /// Returns the token, transparently migrating a legacy plaintext token left
  /// in SharedPreferences by an older build into secure storage on first read.
  Future<String?> read() async {
    if (_loaded) return _cached;

    final secure = await _secure.read(key: _key);
    if (secure != null) {
      _cached = secure;
      _loaded = true;
      return secure;
    }

    final prefs = await SharedPreferences.getInstance();
    final legacy = prefs.getString(_key);
    if (legacy != null) {
      await _secure.write(key: _key, value: legacy);
      await prefs.remove(_key);
    }
    _cached = legacy;
    _loaded = true;
    return legacy;
  }

  Future<void> write(String token) async {
    await _secure.write(key: _key, value: token);
    _cached = token;
    _loaded = true;
  }

  /// Clears the token from secure storage and sweeps any legacy plaintext copy.
  Future<void> clear() async {
    await _secure.delete(key: _key);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
    _cached = null;
    _loaded = true;
  }
}
