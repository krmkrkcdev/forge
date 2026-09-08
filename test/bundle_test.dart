import 'dart:io';

import 'package:forge/src/scaffold.dart';
import 'package:forge/src/templates/bundle.dart';
import 'package:test/test.dart';

import '../tool/bundle_assets.dart' as bundler;

void main() {
  group('şablon paketi', () {
    test('assets/template ile eşzamanlı', () {
      // Şablonu düzenleyip paketi yeniden üretmeyi unutmak sessiz bir
      // hatadır: forge new eski şablonu yazmaya devam eder ve neden eski
      // olduğunu anlamak zordur.
      expect(
        bundler.generateBundle(),
        equals(_currentBundleSource()),
        reason: 'Çalıştırın: dart run tool/bundle_assets.dart',
      );
    });

    test('her şablon dosyasının bir hedefi var', () {
      final scaffold = ProjectScaffold(
        root: '/tmp/x',
        appDir: '/tmp/x/app',
        substitutions: const {},
        log: (_) {},
      );
      final placed = {...scaffold.fileMap.keys, ...ProjectScaffold.spliced};

      for (final path in templatePaths) {
        // backend/ alt ağacı ve app sözleşme testi fileMap yerine
        // copyBackend() döngüsüyle yerleştirilir (bkz. scaffold.dart).
        if (path.startsWith('backend/') || path == 'contract_test.dart') {
          continue;
        }
        expect(
          placed,
          contains(path),
          reason:
              'assets/template/$path hiçbir yere yazılmıyor. '
              'ProjectScaffold.fileMap ya da spliced içine ekleyin.',
        );
      }
    });

    test('eşlemedeki her kaynak gerçekten var', () {
      final scaffold = ProjectScaffold(
        root: '/tmp/x',
        appDir: '/tmp/x/app',
        substitutions: const {},
        log: (_) {},
      );
      for (final source in scaffold.fileMap.keys) {
        if (ProjectScaffold.binary.contains(source)) {
          expect(templateBytes(source), isNotNull, reason: source);
        } else {
          expect(templateFile(source), isNotNull, reason: source);
        }
      }
      for (final source in ProjectScaffold.spliced) {
        expect(templateFile(source), isNotNull, reason: source);
      }
    });

    test('ikili şablon bayt bayt korunur', () {
      // PNG, UTF-8 olarak çözülemez; metin yolundan geçse ya patlar ya da
      // sessizce bozulurdu. İmzayı ve boyutu diskteki kaynakla karşılaştır.
      const logo = 'assets/splash/pikelabs.png';
      final bytes = templateBytes(logo)!;
      expect(bytes.take(4).toList(), [0x89, 0x50, 0x4E, 0x47]);
      expect(bytes, File('assets/template/$logo').readAsBytesSync());
      expect(
        () => ProjectScaffold(
          root: '/tmp/x',
          appDir: '/tmp/x/app',
          substitutions: const {},
          log: (_) {},
        ).render(logo),
        throwsStateError,
      );
    });

    test('yer tutucular dolduruluyor', () {
      final scaffold = ProjectScaffold(
        root: '/tmp/x',
        appDir: '/tmp/x/app',
        substitutions: const {'APP_NAME': 'Denek', 'APP_CLASS': 'DenekApp'},
        log: (_) {},
      );
      final main = scaffold.render('lib/main.dart');
      expect(main, contains('class DenekApp'));
      expect(main, isNot(contains('{{')));
    });
  });
}

/// Diskteki üretilmiş dosyanın metni.
///
/// İçe aktarılmış hâli derlenmiş koddur; karşılaştırma kaynak metin
/// üzerinden yapılmalı.
String _currentBundleSource() =>
    File('lib/src/templates/bundle.dart').readAsStringSync();
