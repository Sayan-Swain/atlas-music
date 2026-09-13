import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:atlas_music/media/media_source.dart';
import 'package:atlas_music/media/providers/saavn_provider.dart';
import 'package:atlas_music/media/resolve_failure.dart';

void main() {
  group('tokenOf', () {
    test('token comes from url last path segment (permalink)', () {
      expect(
        SaavnProvider.tokenOf({'url': 'https://www.jiosaavn.com/song/x/LxAOQS1aZVg'}),
        'LxAOQS1aZVg',
      );
    });

    test('fallback to bare id when url missing', () {
      expect(SaavnProvider.tokenOf({'id': '_xepYjRk'}), '_xepYjRk');
    });

    test('empty when neither present', () {
      expect(SaavnProvider.tokenOf({}), '');
    });
  });

  group('bestSong canonical-title ranking', () {
    test('exact normalized query match wins over a remix variant', () {
      final results = [
        {'title': 'Abhi Toh Party Shuru Hui Hai (Mind Relax Lofi Song)'},
        {'title': 'Abhi Toh Party Shuru Hui Hai'},
        {'title': 'Abhi Toh Party Shuru Hui Hai (From "Khoobsurat")'},
      ];
      final best = SaavnProvider.bestSong(
        results,
        normalizedQuery: SaavnProvider.normalize('Abhi Toh Party Shuru Hui Hai'),
      );
      expect(best?['title'], 'Abhi Toh Party Shuru Hui Hai');
    });

    test('without exact match, shortest title (fewest parentheticals) wins',
        () {
      final results = [
        {'title': 'Believer (Lofi Mix)'},
        {'title': 'Believer'},
      ];
      final best = SaavnProvider.bestSong(results);
      expect(best?['title'], 'Believer');
    });

    test('normalize collapses whitespace and case', () {
      expect(SaavnProvider.normalize('  Abhi   Toh  '), 'abhi toh');
    });

    test('null when no results', () {
      expect(SaavnProvider.bestSong(const []), isNull);
    });
  });

  group('validate preview guard', () {
    MediaSource src({required int? advertised, required int estimated}) =>
        MediaSource(
          provider: MediaProvider.saavn,
          url: 'https://c.saavncdn.com/x.mp3',
          mimeType: 'audio/mpeg',
          codec: 'mp3',
          container: 'mp3',
          contentLength: estimated,
          isProxy: true,
          resolvedAt: DateTime.now(),
        );

    SaavnProvider withHead(int? advertised) => SaavnProvider(
          client: MockClient((_) async => http.Response(
            '',
            200,
            headers: advertised == null
                ? {}
                : {'content-length': '$advertised'},
          )),
        );

    test('rejects preview-length file instead of serving a snippet', () {
      // ~15s of mp3 advertised against a ~3min estimate.
      expect(
        () => withHead(300 * 1024).validate(src(
          advertised: 300 * 1024,
          estimated: 7200 * 1024,
        )),
        throwsA(isA<ResolveFailure>().having(
            (e) => e.scope, 'scope', FailureScope.url)),
      );
    });

    test('accepts full-length file and unknown lengths', () async {
      final full = await withHead(7000 * 1024).validate(src(
        advertised: 7000 * 1024,
        estimated: 7200 * 1024,
      ));
      expect(full.url, contains('saavncdn'));
      final unknown = await withHead(null).validate(src(
        advertised: 0,
        estimated: 7200 * 1024,
      ));
      expect(unknown.url, contains('saavncdn'));
    });
  });
}