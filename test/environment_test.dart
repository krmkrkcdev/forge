import 'dart:io';

import 'package:forge/src/environment.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Kurulu forge'un kaynaktan geri kalıp kalmadığını ölçen iki saf işlev.
///
/// Ortam denetiminin kendisi makineye bakar (PUB_CACHE, `dart pub global
/// list`) ve testte taklit edilmesi anlamsızdır; asıl karar bu iki tarih
/// karşılaştırmasında verilir, test de oraya bakar.
void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('forge_env_'));
  tearDown(() => root.deleteSync(recursive: true));

  File write(String relative, {DateTime? modified}) {
    final file = File(p.join(root.path, relative));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('// x\n');
    if (modified != null) file.setLastModifiedSync(modified);
    return file;
  }

  group('newestForgeSourceChange', () {
    test('kaynak dizini boşsa null döner', () {
      expect(newestForgeSourceChange(root.path), isNull);
    });

    test('lib ve bin altındaki en yeni .dart dosyasını bulur', () {
      final old = DateTime(2026, 1, 1);
      final recent = DateTime(2026, 8, 12);

      write('lib/src/checks.dart', modified: old);
      write('bin/forge.dart', modified: recent);
      write('lib/src/commands/doctor_command.dart', modified: old);

      expect(newestForgeSourceChange(root.path), recent);
    });

    test('pubspec.yaml da sayılır — bağımlılık değişikliği kurulumu etkiler',
        () {
      write('lib/x.dart', modified: DateTime(2026, 1, 1));
      write('pubspec.yaml', modified: DateTime(2026, 9, 1));

      expect(newestForgeSourceChange(root.path), DateTime(2026, 9, 1));
    });

    test('kod olmayan dosyalar sayılmaz', () {
      // README ya da bir şablon metni değişti diye "kurulum eski" demek,
      // uyarıyı görmezden gelinir hâle getirirdi.
      write('lib/x.dart', modified: DateTime(2026, 1, 1));
      write('lib/notlar.md', modified: DateTime(2026, 9, 1));

      expect(newestForgeSourceChange(root.path), DateTime(2026, 1, 1));
    });
  });

  group('installedForgeSnapshotDate', () {
    test('anlık görüntü yoksa null döner — sarmalayıcı her çağrıda derler',
        () {
      expect(
        installedForgeSnapshotDate(sourceDir: root.path, pubCache: root.path),
        isNull,
      );
    });

    test('anlık görüntüyü PROJENİN .dart_tool dizininde bulur', () {
      // Dart 3.x yoldan kurulan paketi buraya derler. PUB_CACHE'te yalnızca
      // sarmalayıcı vardır ve o, activate ile tazelendiği için kurulumun
      // güncelliğini ÖLÇMEZ — bir ay boyunca eski kodun çalışmasının sebebi
      // tam olarak buydu.
      final dir = Directory(p.join(root.path, '.dart_tool', 'pub', 'bin', 'forge'))
        ..createSync(recursive: true);
      File(p.join(dir.path, 'forge.dart-3.10.4.snapshot'))
        ..writeAsStringSync('x')
        ..setLastModifiedSync(DateTime(2026, 8, 5));

      // pubCache bilinçli olarak boş bir dizin: testin makinedeki gerçek
      // ~/.pub-cache içeriğine bağlı olmaması gerekir.
      expect(
        installedForgeSnapshotDate(
          sourceDir: root.path,
          pubCache: p.join(root.path, 'bos-cache'),
        ),
        DateTime(2026, 8, 5),
      );
    });

    test('eski SDK\'ların PUB_CACHE yerleşimini de tanır', () {
      final cache = Directory(p.join(root.path, 'cache'))..createSync();
      final dir = Directory(p.join(cache.path, 'global_packages', 'forge', 'bin'))
        ..createSync(recursive: true);
      File(p.join(dir.path, 'forge.dart-3.9.0.snapshot'))
        ..writeAsStringSync('x')
        ..setLastModifiedSync(DateTime(2026, 1, 1));

      expect(
        installedForgeSnapshotDate(sourceDir: root.path, pubCache: cache.path),
        DateTime(2026, 1, 1),
      );
    });

    test('iki yerleşim de varsa en yenisini alır', () {
      final cache = Directory(p.join(root.path, 'cache'))..createSync();
      final old = Directory(p.join(cache.path, 'global_packages', 'forge', 'bin'))
        ..createSync(recursive: true);
      File(p.join(old.path, 'forge.dart-3.9.0.snapshot'))
        ..writeAsStringSync('x')
        ..setLastModifiedSync(DateTime(2026, 1, 1));

      final current = Directory(p.join(root.path, '.dart_tool', 'pub', 'bin', 'forge'))
        ..createSync(recursive: true);
      File(p.join(current.path, 'forge.dart-3.10.4.snapshot'))
        ..writeAsStringSync('x')
        ..setLastModifiedSync(DateTime(2026, 8, 5));

      expect(
        installedForgeSnapshotDate(sourceDir: root.path, pubCache: cache.path),
        DateTime(2026, 8, 5),
      );
    });
  });
}
