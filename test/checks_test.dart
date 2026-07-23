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

  group('ios-ipad-orientation-mismatch', () {
    /// iPad hedefleyen, verilen ~ipad yönlerine sahip bir proje kurar.
    void writeIosProject({
      required String deviceFamily,
      required List<String> ipadOrientations,
      bool requiresFullScreen = false,
    }) {
      fixture.write(
        'ios/Runner.xcodeproj/project.pbxproj',
        'DEVELOPMENT_TEAM = 26BTDFQ8VY;\n'
        'TARGETED_DEVICE_FAMILY = "$deviceFamily";\n',
      );
      final orientations =
          ipadOrientations.map((o) => '\t\t<string>$o</string>').join('\n');
      fixture.write(
        'ios/Runner/Info.plist',
        '<plist><dict>\n'
        '\t<key>UISupportedInterfaceOrientations~ipad</key>\n'
        '\t<array>\n$orientations\n\t</array>\n'
        '${requiresFullScreen ? '\t<key>UIRequiresFullScreen</key><true/>\n' : ''}'
        '</dict></plist>\n',
      );
    }

    test('iPad hedeflenip yatay yön yoksa ve tam ekran beyanı da yoksa engel', () {
      writeIosProject(
        deviceFamily: '1,2',
        ipadOrientations: [
          'UIInterfaceOrientationPortrait',
          'UIInterfaceOrientationPortraitUpsideDown',
        ],
      );

      final finding =
          findingWithId(fixture.project, 'ios-ipad-orientation-mismatch');
      expect(finding, isNotNull);
      expect(finding!.severity, Severity.blocker);
    });

    test('UIRequiresFullScreen varsa sessiz kalır', () {
      writeIosProject(
        deviceFamily: '1,2',
        ipadOrientations: ['UIInterfaceOrientationPortrait'],
        requiresFullScreen: true,
      );

      expect(
        findingWithId(fixture.project, 'ios-ipad-orientation-mismatch'),
        isNull,
      );
    });

    test('dört yön de beyan edilmişse sessiz kalır', () {
      writeIosProject(
        deviceFamily: '1,2',
        ipadOrientations: [
          'UIInterfaceOrientationPortrait',
          'UIInterfaceOrientationPortraitUpsideDown',
          'UIInterfaceOrientationLandscapeLeft',
          'UIInterfaceOrientationLandscapeRight',
        ],
      );

      expect(
        findingWithId(fixture.project, 'ios-ipad-orientation-mismatch'),
        isNull,
      );
    });

    test('iPad hedeflenmiyorsa kural geçerli değil', () {
      // Yalnızca iPhone hedefleyen uygulamada çoklu görev şartı yok.
      writeIosProject(
        deviceFamily: '1',
        ipadOrientations: ['UIInterfaceOrientationPortrait'],
      );

      expect(
        findingWithId(fixture.project, 'ios-ipad-orientation-mismatch'),
        isNull,
      );
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
