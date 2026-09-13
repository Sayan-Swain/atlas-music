import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:atlas_music/widgets/artwork.dart';

Future<void> _pump(WidgetTester tester, Artwork art) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: Center(child: art)),
    ),
  );
}

Size _fallbackSize(WidgetTester tester) {
  final icon = find.byIcon(Icons.music_note);
  expect(icon, findsOneWidget);
  final box = find.ancestor(of: icon, matching: find.byType(Container)).first;
  return tester.getSize(box);
}

void main() {
  testWidgets('square size honored', (tester) async {
    await _pump(tester, const Artwork('', size: 140));
    expect(_fallbackSize(tester), const Size(140, 140));
  });

  testWidgets('explicit width+height box honored', (tester) async {
    await _pump(
        tester, const Artwork('', width: 150, height: 130, radius: 0));
    expect(_fallbackSize(tester), const Size(150, 130));
  });

  testWidgets('square art fits 360px phone player slot', (tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    // Player slot: screen - 80 (page padding) - 24 (panel padding).
    const slot = 360.0 - 104;
    await _pump(tester, const Artwork('', size: slot));
    expect(_fallbackSize(tester).width, lessThanOrEqualTo(360.0 - 80));
  });

  testWidgets('large art single decode over mist fill', (tester) async {
    // Closed-port URL fails fast: structure asserts need no settle.
    // Perf: one CachedNetworkImage (contain) over cheap mist fill —
    // prior double-stack decoded same URL twice per large card.
    await _pump(
        tester, const Artwork('http://127.0.0.1:9/x.jpg', size: 140));
    expect(find.byType(CachedNetworkImage), findsOneWidget);
    final img =
        tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
    expect(img.fit, BoxFit.contain);
  });

  testWidgets('tiny art stays single cover layer', (tester) async {
    await _pump(
        tester, const Artwork('http://127.0.0.1:9/x.jpg', size: 42));
    expect(find.byType(CachedNetworkImage), findsOneWidget);
  });
}
