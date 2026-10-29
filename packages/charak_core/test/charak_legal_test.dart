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
    testWidgets('"I agree" is there straight away, even on a long document', (tester) async {
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

      // Reading is up to them: no scrolling to the end first.
      expect(find.textContaining('End of the Practitioner Agreement'), findsNothing);
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

    testWidgets('each document is ticked on its own, read or not', (tester) async {
      _serve(_doc());
      final reports = <bool>[];
      final privacy = CharakLegalDocument.fromJson({..._doc(), 'type': 'privacy', 'title': 'Privacy Policy'});
      await tester.pumpWidget(_app(Scaffold(
        body: CharakAgreementsList(
          documents: [CharakLegalDocument.fromJson(_doc()), privacy],
          onAllAgreed: reports.add,
        ),
      )));
      expect(find.textContaining('I agree to the', findRichText: true), findsNWidgets(2));

      // The box itself; the title is a link.
      Future<void> tick(Finder row) => tester.tapAt(tester.getRect(row).centerLeft + const Offset(12, 0));

      // Ticked straight from the list, without opening it.
      await tick(find.byType(CharakCheckRow).last);
      await tester.pumpAndSettle();
      expect(reports, [false]);

      // The title opens the full text in the app; agreeing there ticks it too.
      await tester.tapOnText(find.textRange.ofSubstring('Practitioner Agreement'));
      await tester.pumpAndSettle();
      expect(find.text('You practise independently.'), findsOneWidget);
      await tester.tap(find.widgetWithText(CharakButton, 'I agree'));
      await tester.pumpAndSettle();
      expect(reports, [false, true]);

      // And a tick can be taken back.
      await tick(find.byType(CharakCheckRow).first);
      await tester.pumpAndSettle();
      expect(reports, [false, true, false]);
    });
  });

  testWidgets('the cancellation rules summarise, and every case is a tap away', (tester) async {
    var readPolicy = 0;
    await tester.pumpWidget(_app(Scaffold(
      body: SingleChildScrollView(
        child: CharakCancellationRules(
          policy: const {
            'channel': 'home_visit',
            'summary': 'Cancel any time before it starts.',
            'points': [
              {'when': '2 hours or more before the visit', 'outcome': 'Full refund', 'tone': 'full', 'by': 'patient'},
              {'when': "Less than 2 hours before the visit, if the doctor hasn't set out",
               'outcome': '50% refund', 'tone': 'partial', 'by': 'patient'},
              {'when': 'After the doctor has set out', 'outcome': 'No refund', 'tone': 'none', 'by': 'patient'},
              {'when': "Doctor hasn't arrived 30 minutes in", 'outcome': 'Full refund', 'tone': 'full', 'by': 'doctor',
               'note': "Or choose another doctor. If you don't choose within 24 hours, you're refunded."},
              // A backend from before `by`: sorted by its wording.
              {'when': "The doctor can't keep the time", 'outcome': 'New time or full refund', 'tone': 'choice'},
            ],
            'refund_timing': 'Refunds go back to the way you paid.',
          },
          onReadPolicy: () => readPolicy++,
        ),
      ),
    )));
    await tester.pumpAndSettle();
    // The card: when free cancellation ends and one line on what follows.
    expect(find.text('Free cancellation until the visit'), findsOneWidget);
    expect(find.text('After that, a partial refund or none, depending on timing.'), findsOneWidget);
    expect(find.text('50% refund'), findsNothing);

    // The sheet: every case, the timing and the full policy.
    await tester.tap(find.text('View details'));
    await tester.pumpAndSettle();
    expect(find.text("Less than 2 hours before the visit, if the doctor hasn't set out"), findsOneWidget);
    expect(find.text('50% refund'), findsOneWidget);
    expect(find.text('No refund'), findsOneWidget);
    // Two tables: the patient's rows, then the doctor's (old wording included).
    expect(find.text('IF YOU CANCEL'), findsOneWidget);
    expect(find.text("IF THE DOCTOR CAN'T MAKE IT"), findsOneWidget);
    double top(String text) => tester.getTopLeft(find.text(text)).dy;
    expect(top("IF THE DOCTOR CAN'T MAKE IT"), greaterThan(top('After the doctor has set out')));
    expect(top("The doctor can't keep the time"), greaterThan(top("IF THE DOCTOR CAN'T MAKE IT")));
    expect(find.text("Or choose another doctor. If you don't choose within 24 hours, you're refunded."), findsOneWidget);
    expect(find.text('Refunds go back to the way you paid.'), findsOneWidget);
    expect(find.text('Cancel any time before it starts.'), findsNothing);   // the summary is the fallback
    await tester.ensureVisible(find.text('Read the full policy'));
    await tester.tap(find.text('Read the full policy'));
    expect(readPolicy, 1);

    await tester.ensureVisible(find.text('Got it'));
    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
    expect(find.text('50% refund'), findsNothing);
  });
}
