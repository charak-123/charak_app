import 'dart:convert';

import 'package:charak_core/charak_core.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A backend that answers from a script, recording every request it sees.
class _Script {
  final List<Object> steps; // http.Response, or an Exception to throw
  final List<http.Request> seen = [];
  _Script(this.steps);

  MockClient get client => MockClient((req) async {
        seen.add(req);
        final step = steps[seen.length - 1];
        if (step is Exception) throw step;
        return step as http.Response;
      });
}

http.Response _ok([Object body = const {'ok': true}]) =>
    http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    ApiClient.retryBackoff = const [Duration.zero, Duration.zero];
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() => ApiClient.debugClient = null);

  void signedIn([bool yes = true]) =>
      FlutterSecureStorage.setMockInitialValues(yes ? {'auth_token': 'tok'} : {});

  test('a signed-in write carries an idempotency key', () async {
    signedIn();
    final s = _Script([_ok()]);
    ApiClient.debugClient = s.client;
    await ApiClient.instance.post('/bookings/', {'a': 1});
    final key = s.seen.single.headers['Idempotency-Key'];
    expect(key, matches(RegExp(r'^[0-9a-f]{32}$')));
  });

  test('a dropped connection is retried with the same key', () async {
    signedIn();
    final s = _Script([http.ClientException('connection reset'), _ok()]);
    ApiClient.debugClient = s.client;
    final res = await ApiClient.instance.patch('/bookings/bk-1/cancel', {});
    expect(res, {'ok': true});
    expect(s.seen, hasLength(2));
    expect(s.seen[0].headers['Idempotency-Key'], s.seen[1].headers['Idempotency-Key']);
  });

  test('a request still running on the server is asked about again', () async {
    signedIn();
    final s = _Script([
      http.Response('{"error":"already being processed"}', 409, headers: {'retry-after': '1'}),
      _ok(),
    ]);
    ApiClient.debugClient = s.client;
    expect(await ApiClient.instance.post('/payments/bk-1/order', {}), {'ok': true});
    expect(s.seen, hasLength(2));
  });

  test('retries stop after the backoff list and the error surfaces', () async {
    signedIn();
    final s = _Script(List.filled(3, http.ClientException('down')));
    ApiClient.debugClient = s.client;
    await expectLater(ApiClient.instance.post('/x', {}),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 0)));
    expect(s.seen, hasLength(3));
  });

  test('a real answer, even an error, is never retried', () async {
    signedIn();
    final s = _Script([http.Response('{"error":"Slot already booked"}', 409)]);
    ApiClient.debugClient = s.client;
    await expectLater(ApiClient.instance.post('/bookings/', {}),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 409)));
    expect(s.seen, hasLength(1));
  });

  test('sign-in calls carry no key and are never retried', () async {
    signedIn(false);
    final s = _Script([http.ClientException('down')]);
    ApiClient.debugClient = s.client;
    await expectLater(ApiClient.instance.post('/auth/send-otp', {}), throwsA(isA<ApiException>()));
    expect(s.seen, hasLength(1));
    expect(s.seen.single.headers.containsKey('Idempotency-Key'), isFalse);
  });

  test('a caller can pin the key across its own retries', () async {
    signedIn();
    final s = _Script([_ok(), _ok()]);
    ApiClient.debugClient = s.client;
    await ApiClient.instance.post('/x', {}, idempotencyKey: 'order-attempt-1234');
    await ApiClient.instance.post('/x', {}, idempotencyKey: 'order-attempt-1234');
    expect(s.seen.map((r) => r.headers['Idempotency-Key']).toSet(), {'order-attempt-1234'});
  });
}
