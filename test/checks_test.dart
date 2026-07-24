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

  group('reklam denetimleri', () {
    /// Reklam gösteren bir projeyi verilen yerel yapılandırmayla kurar.
    void writeAdProject({
      String? iosAppId,
      String? androidAppId,
      bool consentInCode = false,
      bool skAdNetwork = false,
    }) {
      fixture.write(
        'pubspec.yaml',
        'name: denek\nversion: 1.0.0+1\n'
        'dependencies:\n  google_mobile_ads: ^9.0.0\n',
      );
      fixture.write(
        'ios/Runner/Info.plist',
        '<plist><dict>\n'
        '${iosAppId == null ? '' : '\t<key>GADApplicationIdentifier</key><string>$iosAppId</string>\n'}'
        '${skAdNetwork ? '\t<key>SKAdNetworkItems</key><array/>\n' : ''}'
        '</dict></plist>\n',
      );
      fixture.write(
        'android/app/src/main/AndroidManifest.xml',
        '<manifest><application>\n'
        '${androidAppId == null ? '' : '<meta-data android:name="com.google.android.gms.ads.APPLICATION_ID" android:value="$androidAppId"/>\n'}'
        '</application></manifest>\n',
      );
      fixture.write(
        'lib/services/ad_service.dart',
        consentInCode
            ? 'void f() => ConsentInformation.instance.canRequestAds();\n'
            : 'void f() {}\n',
      );
    }

    const realIos = 'ca-app-pub-4293530643595446~1065274421';
    const realAndroid = 'ca-app-pub-4293530643595446~2065274422';
    const testId = 'ca-app-pub-3940256099942544~3347511713';

    test('reklam paketi yoksa hiçbir reklam kuralı çalışmaz', () {
      fixture.write('ios/Runner/Info.plist', '<plist><dict></dict></plist>');
      for (final id in [
        'admob-app-id-missing',
        'admob-test-app-id',
        'admob-consent-missing',
        'ios-skadnetwork-missing',
      ]) {
        expect(findingWithId(fixture.project, id), isNull, reason: id);
      }
    });

    test('uygulama kimliği eksikse engel — SDK açılışta çökertir', () {
      writeAdProject(androidAppId: realAndroid);

      final finding = findingWithId(fixture.project, 'admob-app-id-missing');
      expect(finding, isNotNull);
      expect(finding!.severity, Severity.blocker);
      expect(finding.title, contains('Info.plist'));
      expect(finding.title, isNot(contains('AndroidManifest')));
    });

    test('test uygulama kimliği hangi platformdaysa onu söyler', () {
      // Asıl tuzak bu: iOS gerçek kimliği alır, Android unutulur ve
      // Android tarafı sessizce sıfır gelir getirir.
      writeAdProject(iosAppId: realIos, androidAppId: testId);

      final finding = findingWithId(fixture.project, 'admob-test-app-id');
      expect(finding, isNotNull);
      expect(finding!.platform, Platform.android);
      expect(finding.title, contains('Android'));
    });

    test('iki platform da gerçek kimlikteyse sessiz kalır', () {
      writeAdProject(iosAppId: realIos, androidAppId: realAndroid);
      expect(findingWithId(fixture.project, 'admob-test-app-id'), isNull);
      expect(findingWithId(fixture.project, 'admob-app-id-missing'), isNull);
    });

    test('onay akışı kodda yoksa uyarır', () {
      writeAdProject(iosAppId: realIos, androidAppId: realAndroid);

      final finding = findingWithId(fixture.project, 'admob-consent-missing');
      expect(finding, isNotNull);
      expect(finding!.severity, Severity.warning);
    });

    test('onay akışı koddaysa sessiz kalır', () {
      writeAdProject(
        iosAppId: realIos,
        androidAppId: realAndroid,
        consentInCode: true,
      );
      expect(findingWithId(fixture.project, 'admob-consent-missing'), isNull);
    });

    test('SKAdNetworkItems eksikse uyarır, varsa susar', () {
      writeAdProject(iosAppId: realIos, androidAppId: realAndroid);
      expect(findingWithId(fixture.project, 'ios-skadnetwork-missing'), isNotNull);

      writeAdProject(
        iosAppId: realIos,
        androidAppId: realAndroid,
        skAdNetwork: true,
      );
      expect(findingWithId(fixture.project, 'ios-skadnetwork-missing'), isNull);
    });

    test('gizlilik manifesti reklamdan söz etmiyorsa uyarır', () {
      writeAdProject(iosAppId: realIos, androidAppId: realAndroid);
      fixture.write(
        'ios/Runner/PrivacyInfo.xcprivacy',
        '<plist><dict><key>NSPrivacyTracking</key><false/></dict></plist>',
      );

      expect(
        findingWithId(fixture.project, 'privacy-manifest-ignores-ads'),
        isNotNull,
      );
    });

    test('reklam verisi beyan edilmişse sessiz kalır', () {
      writeAdProject(iosAppId: realIos, androidAppId: realAndroid);
      fixture.write(
        'ios/Runner/PrivacyInfo.xcprivacy',
        '<plist><dict>'
        '<string>NSPrivacyCollectedDataTypeDeviceID</string>'
        '</dict></plist>',
      );

      expect(
        findingWithId(fixture.project, 'privacy-manifest-ignores-ads'),
        isNull,
      );
    });

    test('ATT paketi varken açıklama metni yoksa engel', () {
      fixture.write(
        'pubspec.yaml',
        'name: denek\nversion: 1.0.0+1\n'
        'dependencies:\n  app_tracking_transparency: ^2.0.0\n',
      );
      fixture.write('ios/Runner/Info.plist', '<plist><dict></dict></plist>');

      final finding =
          findingWithId(fixture.project, 'ios-tracking-usage-description');
      expect(finding, isNotNull);
      expect(finding!.severity, Severity.blocker);
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
