import 'dart:io';

import 'package:forge/src/checks.dart';
import 'package:forge/src/finding.dart';
import 'package:forge/src/project.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Geçici bir Flutter projesi kurar.
///
/// Denetimler dosya sistemine ve git'e bakıyor; sahte nesne yerine gerçek
/// dosya kullanmak testi hem daha basit hem de daha dürüst yapıyor.
class _Fixture {
  _Fixture() : root = Directory.systemTemp.createTempSync('forge_test_');

  final Directory root;

  FlutterProject get project => FlutterProject(root.path);

  void write(String relative, String content) {
    final file = File(p.join(root.path, relative));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  void gitInit() {
    Process.runSync('git', ['init', '-q', '.'], workingDirectory: root.path);
  }

  void dispose() => root.deleteSync(recursive: true);
}

/// Verilen kimliğe sahip bulguyu döndürür; yoksa null.
Finding? findingWithId(FlutterProject project, String id) {
  for (final finding in runChecks(project)) {
    if (finding.id == id) return finding;
  }
  return null;
}

void main() {
  late _Fixture fixture;

  setUp(() {
    fixture = _Fixture();
    fixture.write('pubspec.yaml', 'name: denek\nversion: 1.0.0+1\n');
  });

  tearDown(() => fixture.dispose());

  group('secrets-not-ignored', () {
    test('git deposu değilse sessiz kalır', () {
      // Denetim yapılamadı demek, "sorun yok" demek değil — ama kullanıcıya
      // eyleme dönüşmeyen bir uyarı göstermenin de faydası yok.
      expect(unprotectedSecrets(fixture.project), isNull);
      expect(findingWithId(fixture.project, 'secrets-not-ignored'), isNull);
    });

    test('.gitignore yokken bütün sır türlerini bildirir', () {
      fixture.gitInit();

      final unprotected = unprotectedSecrets(fixture.project);
      expect(unprotected, hasLength(secretKinds.length));

      final finding = findingWithId(fixture.project, 'secrets-not-ignored');
      expect(finding, isNotNull);
      expect(finding!.severity, Severity.blocker);
      expect(finding.autoFixable, isTrue);
    });

    test('yalnızca korunmayan türleri bildirir', () {
      fixture.gitInit();
      fixture.write('.gitignore', '.env\n*.jks\n*.keystore\nkey.properties\n');

      final labels =
          unprotectedSecrets(fixture.project)!.map((k) => k.label).toList();
      expect(labels, hasLength(2));
      expect(labels.join(), contains('.p8'));
      expect(labels.join(), contains('Google Play'));
    });

    test('hepsi korunuyorsa bulgu üretmez', () {
      fixture.gitInit();
      fixture.write('.gitignore',
          secretKinds.map((k) => k.pattern).toSet().join('\n'));

      expect(unprotectedSecrets(fixture.project), isEmpty);
      expect(findingWithId(fixture.project, 'secrets-not-ignored'), isNull);
    });

    test('dosya var olmasa da açığı bulur', () {
      // Asıl mesele bu: anahtarlar .gitignore yazıldıktan sonra yerine konur.
      // Kural yalnızca var olan dosyalara baksaydı tam da tehlike anında
      // sessiz kalırdı.
      fixture.gitInit();
      expect(File(p.join(fixture.root.path, '.env')).existsSync(), isFalse);
      expect(unprotectedSecrets(fixture.project), isNotEmpty);
    });
  });

  group('ios-no-development-team', () {
    test('iOS klasörü yoksa sessiz kalır', () {
      expect(findingWithId(fixture.project, 'ios-no-development-team'), isNull);
    });

    test('DEVELOPMENT_TEAM yoksa engel bildirir', () {
      fixture.write('ios/Runner.xcodeproj/project.pbxproj',
          'CODE_SIGN_STYLE = Automatic;\n');

      final finding = findingWithId(fixture.project, 'ios-no-development-team');
      expect(finding, isNotNull);
      expect(finding!.severity, Severity.blocker);
    });

    test('DEVELOPMENT_TEAM varsa sessiz kalır', () {
      fixture.write('ios/Runner.xcodeproj/project.pbxproj',
          'DEVELOPMENT_TEAM = 26BTDFQ8VY;\n');

      expect(findingWithId(fixture.project, 'ios-no-development-team'), isNull);
    });
  });
}
