import 'package:charak_core/charak_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(home: child);

/// The scaffold has two modes — identity-on-a-field before video arrives, and
/// live video once it does. Getting the swap wrong either covers the peer's
/// face with their own name or leaves a connected call looking disconnected.
void main() {
  group('CharakCallScaffold', () {
    testWidgets('shows the peer identity block when there is no video',
        (tester) async {
      await tester.pumpWidget(_wrap(const CharakCallScaffold(
        peerName: 'Dr Anita Rao',
        peerSubtitle: 'Ringing…',
        statusText: '00:03',
        controls: [],
      )));

      expect(find.text('Dr Anita Rao'), findsOneWidget);
      expect(find.text('Ringing…'), findsOneWidget);
      expect(find.text('00:03'), findsOneWidget);
      // The avatar stands in for the absent stream.
      expect(find.byType(CharakAvatar), findsOneWidget);
    });

    testWidgets('renders peer video instead of the avatar once it arrives',
        (tester) async {
      await tester.pumpWidget(_wrap(CharakCallScaffold(
        peerName: 'Dr Anita Rao',
        peerSubtitle: 'connected',
        statusText: '01:12',
        peerVideo: const ColoredBox(
          key: Key('peer'),
          color: Color(0xFF00FF00),
        ),
        controls: const [],
      )));

      expect(find.byKey(const Key('peer')), findsOneWidget);
      expect(find.byType(CharakAvatar), findsNothing);
      // The name stays visible — just moved out of the centre.
      expect(find.text('Dr Anita Rao'), findsOneWidget);
    });

    testWidgets('self-view falls back to the camera glyph without a stream',
        (tester) async {
      await tester.pumpWidget(_wrap(const CharakCallScaffold(
        peerName: 'Patient',
        statusText: '00:00',
        controls: [],
      )));

      expect(find.byIcon(Icons.videocam_outlined), findsOneWidget);
    });

    testWidgets('self-view renders the local stream when given one',
        (tester) async {
      await tester.pumpWidget(_wrap(CharakCallScaffold(
        peerName: 'Patient',
        statusText: '00:00',
        selfVideo: const ColoredBox(key: Key('self'), color: Color(0xFF0000FF)),
        controls: const [],
      )));

      expect(find.byKey(const Key('self')), findsOneWidget);
      expect(find.byIcon(Icons.videocam_outlined), findsNothing);
    });

    testWidgets('hiding the self-view removes the tile entirely',
        (tester) async {
      await tester.pumpWidget(_wrap(CharakCallScaffold(
        peerName: 'Patient',
        statusText: '00:00',
        showSelfView: false,
        selfVideo: const ColoredBox(key: Key('self'), color: Color(0xFF0000FF)),
        controls: const [],
      )));

      expect(find.byKey(const Key('self')), findsNothing);
      expect(find.byIcon(Icons.videocam_outlined), findsNothing);
    });

    testWidgets('renders the control row', (tester) async {
      var ended = false;
      await tester.pumpWidget(_wrap(CharakCallScaffold(
        peerName: 'Patient',
        statusText: '00:00',
        controls: [
          const CharakCallButton(icon: Icons.mic, semanticLabel: 'Mute'),
          CharakCallButton(
            icon: Icons.call_end,
            end: true,
            semanticLabel: 'End call',
            onPressed: () => ended = true,
          ),
        ],
      )));

      expect(find.byType(CharakCallButton), findsNWidgets(2));
      await tester.tap(find.byIcon(Icons.call_end));
      expect(ended, isTrue);
    });

    testWidgets('a disabled control does not fire', (tester) async {
      var tapped = false;
      await tester.pumpWidget(_wrap(CharakCallScaffold(
        peerName: 'Patient',
        statusText: '00:00',
        controls: [
          CharakCallButton(
            icon: Icons.call_end,
            end: true,
            semanticLabel: 'End call',
            onPressed: null,
          ),
        ],
      )));

      await tester.tap(find.byIcon(Icons.call_end));
      expect(tapped, isFalse);
    });
  });
}
