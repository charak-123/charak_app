import 'package:charak_core/charak_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// `isStub` decides whether an Agora engine is created at all, so the parsing
/// that feeds it is worth pinning: a misread response either fails to connect a
/// real call or tries to join a channel that does not exist.
void main() {
  group('CharakCallCredentials.fromJson', () {
    test('reads the doctor initiate response', () {
      final creds = CharakCallCredentials.fromJson({
        'id': 'call-1',
        'agora_channel': 'charak_ab12cd34',
        'agora_token': 'real-token',
        'agora_app_id': 'app-id',
        'live': true,
      }, uid: 0);

      expect(creds.channel, 'charak_ab12cd34');
      expect(creds.token, 'real-token');
      expect(creds.uid, 0);
      expect(creds.isStub, isFalse);
    });

    test('prefers the uid the server echoed back over the requested one', () {
      final creds = CharakCallCredentials.fromJson({
        'agora_channel': 'charak_ab12cd34',
        'agora_token': 'real-token',
        'agora_app_id': 'app-id',
        'live': true,
        'uid': 1001,
      }, uid: 7);

      expect(creds.uid, 1001);
    });

    test('accepts the patient endpoint\'s legacy `token` key', () {
      final creds = CharakCallCredentials.fromJson({
        'token': 'real-token',
        'agora_channel': 'charak_ab12cd34',
        'agora_app_id': 'app-id',
        'live': true,
      }, uid: 1001);

      expect(creds.token, 'real-token');
      expect(creds.isStub, isFalse);
    });

    test('treats an unconfigured backend as a stub', () {
      final creds = CharakCallCredentials.fromJson({
        'agora_channel': 'charak_ab12cd34',
        'agora_token': 'stub_token_charak_ab12cd34_0_1700000000',
        'agora_app_id': null,
        'live': false,
      }, uid: 0);

      expect(creds.isStub, isTrue);
    });

    test('infers stub mode from the token prefix when `live` is absent', () {
      final creds = CharakCallCredentials.fromJson({
        'agora_channel': 'charak_ab12cd34',
        'agora_token': 'stub_token_charak_ab12cd34_0_1700000000',
        'agora_app_id': 'app-id',
      }, uid: 0);

      expect(creds.isStub, isTrue);
    });

    test('a live flag with no channel is still a stub', () {
      // Better to show "not configured" than to join an empty channel name.
      final creds = CharakCallCredentials.fromJson({
        'agora_token': 'real-token',
        'agora_app_id': 'app-id',
        'live': true,
      }, uid: 0);

      expect(creds.channel, '');
      expect(creds.isStub, isTrue);
    });

    test('falls back to the caller-supplied channel', () {
      final creds = CharakCallCredentials.fromJson(
        {'token': 'real-token', 'agora_app_id': 'app-id', 'live': true},
        uid: 1001,
        channelFallback: 'charak_ab12cd34',
      );

      expect(creds.channel, 'charak_ab12cd34');
      expect(creds.isStub, isFalse);
    });
  });
}
