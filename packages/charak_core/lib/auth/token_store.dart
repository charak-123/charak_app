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
    final secure = await _secure.read(key: _key);
    if (secure != null) return secure;

    final prefs = await SharedPreferences.getInstance();
    final legacy = prefs.getString(_key);
    if (legacy != null) {
      await _secure.write(key: _key, value: legacy);
      await prefs.remove(_key);
      return legacy;
    }
    return null;
  }

  Future<void> write(String token) => _secure.write(key: _key, value: token);

  /// Clears the token from secure storage and sweeps any legacy plaintext copy.
  Future<void> clear() async {
    await _secure.delete(key: _key);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
