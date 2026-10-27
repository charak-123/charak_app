import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:charak_core/charak_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Uint8List> _png(int width, int height) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xFF3366FF),
  );
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

Future<Size> _decodedSize(ImageProvider provider) {
  final done = Completer<Size>();
  final stream = provider.resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  listener = ImageStreamListener((info, _) {
    done.complete(Size(info.image.width.toDouble(), info.image.height.toDouble()));
    stream.removeListener(listener);
  }, onError: (e, s) => done.completeError(e, s));
  stream.addListener(listener);
  return done.future;
}

void main() {
  group('CharakCoverResizeImage', () {
    testWidgets('decodes the shorter side at the avatar size, keeping the aspect', (tester) async {
      await tester.runAsync(() async {
        final landscape = await _decodedSize(CharakCoverResizeImage(MemoryImage(await _png(800, 600)), 104));
        expect(landscape, const Size(139, 104));
        final portrait = await _decodedSize(CharakCoverResizeImage(MemoryImage(await _png(600, 800)), 104));
        expect(portrait, const Size(104, 139));
      });
    });

    testWidgets('never upscales a photo smaller than the avatar', (tester) async {
      await tester.runAsync(() async {
        final small = await _decodedSize(CharakCoverResizeImage(MemoryImage(await _png(50, 40)), 104));
        expect(small, const Size(50, 40));
      });
    });

    test('sizes are part of the cache key', () {
      const url = NetworkImage('https://example.com/a.jpg');
      expect(const CharakCoverResizeImage(url, 104), const CharakCoverResizeImage(url, 104));
      expect(const CharakCoverResizeImage(url, 104), isNot(const CharakCoverResizeImage(url, 156)));
    });
  });

  testWidgets('CharakAvatar decodes its photo for the device pixel ratio', (tester) async {
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(
      home: Center(child: CharakAvatar(name: 'Asha Rao', imageUrl: 'https://example.com/a.jpg', radius: 26)),
    ));
    final image = tester.widget<Image>(find.byType(Image)).image as CharakCoverResizeImage;
    expect(image.side, 156); // 52 logical px × 3
    expect(image.image, const NetworkImage('https://example.com/a.jpg'));
  });
}
