import 'dart:convert';

import 'package:charak_core/charak_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A document long enough to need scrolling on a phone.
final _longBody = [
  for (var i = 1; i <= 12; i++) '## $i. Section $i\n\n${'A sentence of the agreement. ' * 30}\n',
].join('\n');

Map<String, dynamic> _doc({String body = '## One\n\nShort.\n'}) => {
      'type': 'practitioner_terms',
      'version': '2026-10-28',
      'title': 'Practitioner Agreement',
      'url': 'https://www.charak.care/practitioner-terms',
      'summary': 'The agreement for taking bookings.',
      'highlights': ['You practise independently.'],
      'published_at': '2026-10-28T00:00:00+00:00',
      'sha256': '93635ff47121aaaa93635ff47121aaaa',
      'has_text': true,
      'body': body,
    };

void _serve(Map<String, dynamic> doc) {
  ApiClient.debugClient = MockClient((req) async =>
      http.Response(jsonEncode(doc), 200, headers: {'content-type': 'application/json'}));
}

Widget _app(Widget child) => MaterialApp(theme: charakTheme(), home: child);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });
  tearDown(() => ApiClient.debugClient = null);

  group('the text', () {
    test('reads headings, paragraphs, lists and two-column tables', () {
      final blocks = CharakLegalText.parse('''
## 1. Fees

You keep **the full fee** you set,
across two lines.

- one
- two
  continued

1. first
2. second

### Providers

| Provider | What for |
|---|---|
| Razorpay | Payments |
''');
      expect([for (final b in blocks) b.kind], ['h2', 'p', 'ul', 'ol', 'h3', 'table']);
      expect(blocks[1].text, 'You keep **the full fee** you set, across two lines.');
      expect(blocks[2].rows, [['one'], ['two continued']]);
      expect(blocks[3].rows, [['first'], ['second']]);
      expect(blocks[5].rows, [['Provider', 'What for'], ['Razorpay', 'Payments']]);
    });

    test('bold and italic become runs, not asterisks', () {
      final span = CharakLegalText.inline('A **bold** and *quiet* word', CharakText.body);
      final text = span.toPlainText();
      expect(text, 'A bold and quiet word');
    });
  });

  group('signing', () {
    testWidgets('"I agree" wakes up only at the end of the document', (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 800 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      _serve(_doc(body: _longBody));

      bool? agreed;
      await tester.pumpWidget(_app(Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () async => agreed = await CharakLegalReaderScreen.open(
              context,
              CharakLegalDocument.fromJson(_doc()),
              signing: true,
            ),
            child: const Text('open'),
          ),
        ),
      )));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      CharakButton agree() => tester.widget<CharakButton>(find.widgetWithText(CharakButton, 'I agree'));
      expect(find.text('Read to the end to agree.'), findsOneWidget);
      expect(agree().onPressed, isNull);

      await tester.dragUntilVisible(
        find.textContaining('End of the Practitioner Agreement'),
        find.byType(ListView),
        const Offset(0, -600),
      );
      await tester.pumpAndSettle();
      expect(agree().onPressed, isNotNull);

      await tester.tap(find.widgetWithText(CharakButton, 'I agree'));
      await tester.pumpAndSettle();
      expect(agreed, isTrue);
    });

    testWidgets('a short document can be agreed to straight away', (tester) async {
      _serve(_doc());
      await tester.pumpWidget(_app(const CharakLegalReaderScreen(
        type: 'practitioner_terms',
        title: 'Practitioner Agreement',
        signing: true,
      )));
      await tester.pumpAndSettle();
      expect(find.text('You practise independently.'), findsOneWidget);   // the key points
      expect(tester.widget<CharakButton>(find.widgetWithText(CharakButton, 'I agree')).onPressed, isNotNull);
    });

    testWidgets('the list reports once every document is agreed', (tester) async {
      _serve(_doc());
      final reports = <bool>[];
      await tester.pumpWidget(_app(Scaffold(
        body: CharakAgreementsList(
          documents: [CharakLegalDocument.fromJson(_doc())],
          onAllAgreed: reports.add,
        ),
      )));
      expect(find.text('Read and agree'), findsOneWidget);

      await tester.tap(find.text('Practitioner Agreement'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CharakButton, 'I agree'));
      await tester.pumpAndSettle();

      expect(reports, [true]);
      expect(find.text('Agreed'), findsOneWidget);
    });
  });

  testWidgets('the cancellation rules show every case', (tester) async {
    await tester.pumpWidget(_app(const Scaffold(
      body: SingleChildScrollView(
        child: CharakCancellationRules(policy: {
          'channel': 'online_consult',
          'summary': 'Cancel any time before it starts.',
          'points': [
            {'when': 'You cancel any time before the consultation starts', 'outcome': 'Full refund', 'tone': 'full'},
            {'when': 'You miss the consultation', 'outcome': 'No refund', 'tone': 'none'},
          ],
          'refund_timing': 'Refunds go back to the way you paid.',
        }),
      ),
    )));
    await tester.pumpAndSettle();
    expect(find.text('Free cancellation until the consultation starts'), findsOneWidget);
    expect(find.text('You miss the consultation'), findsOneWidget);
    expect(find.text('No refund'), findsOneWidget);
    expect(find.text('Cancel any time before it starts.'), findsNothing);   // the summary is the fallback
  });
}
