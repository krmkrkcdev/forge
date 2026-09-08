import 'package:forge/src/native_patch.dart';
import 'package:test/test.dart';

/// `flutter create` çıktısının ilgili parçaları.
///
/// Gerçek dosyalar uzun; yamaların dayandığı çıpaları birebir taşıyan en
/// küçük örnekler burada. Çıpalardan biri Flutter tarafında değişirse
/// testler değil gerçek proje kırılır — bu yüzden yamalar sorun bildirmeyi
/// biliyor ve testler bunu da sınıyor.
const _infoPlist = '''
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
	<key>CFBundleName</key>
	<string>denek</string>
</dict>
</plist>
''';

const _pbxproj = '''
/* Begin PBXBuildFile section */
		97C147011CF9000F007C117D /* LaunchScreen.storyboard in Resources */ = {isa = PBXBuildFile; fileRef = 97C146FF1CF9000F007C117D /* LaunchScreen.storyboard */; };
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
		97C146EE1CF9000F007C117D /* Runner.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; path = Runner.app; sourceTree = BUILT_PRODUCTS_DIR; };
/* End PBXFileReference section */

/* Begin PBXGroup section */
		97C146F01CF9000F007C117D /* Runner */ = {
			isa = PBXGroup;
			children = (
				97C146FA1CF9000F007C117D /* Main.storyboard */,
			);
			path = Runner;
			sourceTree = "<group>";
		};
/* End PBXGroup section */

/* Begin PBXResourcesBuildPhase section */
		331C807F294A63A400263BE5 /* Resources */ = {
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
		97C146EC1CF9000F007C117D /* Resources */ = {
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				97C147011CF9000F007C117D /* LaunchScreen.storyboard in Resources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXResourcesBuildPhase section */
''';

const _androidManifest = '''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application
        android:label="denek"
        android:name="\${applicationName}"
        android:icon="@mipmap/ic_launcher">
        <activity android:name=".MainActivity"/>
    </application>
</manifest>
''';

const _buildGradle = '''
plugins {
    id("com.android.application")
}

android {
    namespace = "com.denek.app"

    defaultConfig {
        applicationId = "com.denek.app"
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
''';

void main() {
  _developmentTeamTests();
  group('patchInfoPlist', () {
    test('anahtarları son </dict> önüne ekler', () {
      final result = patchInfoPlist(
        _infoPlist,
        '\t<key>GADApplicationIdentifier</key>\n\t<string>x</string>\n',
      );

      expect(result.ok, isTrue);
      expect(result.content, contains('GADApplicationIdentifier'));
      expect(result.content.trim(), endsWith('</plist>'));
      expect(result.content, contains('CFBundleName'));
    });

    test('zaten uygulanmışsa dosyaya dokunmaz', () {
      final once = patchInfoPlist(
        _infoPlist,
        '\t<key>GADApplicationIdentifier</key>\n',
      ).content;
      final twice = patchInfoPlist(
        once,
        '\t<key>GADApplicationIdentifier</key>\n',
      ).content;

      expect(twice, equals(once));
    });

    test('beklenmedik yapıda sorunu bildirir', () {
      final result = patchInfoPlist('bu bir plist değil', '<key>x</key>');

      expect(result.ok, isFalse);
      expect(result.content, equals('bu bir plist değil'));
    });
  });

  group('registerPrivacyManifest', () {
    test('dosyayı Copy Bundle Resources fazına ekler', () {
      // Asıl mesele bu: gruba eklemek dosyayı pakete SOKMAZ. Faza
      // eklenmezse Apple dosyayı hiç görmez.
      final result = registerPrivacyManifest(_pbxproj);

      expect(result.ok, isTrue);
      final resources = result.content.substring(
        result.content.indexOf('97C146EC1CF9000F007C117D /* Resources */'),
      );
      expect(resources, contains('PrivacyInfo.xcprivacy in Resources'));
    });

    test('uygulama hedefinin fazını seçer, test hedefininkini değil', () {
      final result = registerPrivacyManifest(_pbxproj);
      final bosFaz = result.content.substring(
        result.content.indexOf('331C807F294A63A400263BE5'),
        result.content.indexOf('97C146EC1CF9000F007C117D /* Resources */'),
      );

      expect(bosFaz, isNot(contains('PrivacyInfo')));
    });

    test('dört bölümün hepsine kaydeder', () {
      // Xcode bir dosyayı ancak dört yerde birden görürse pakete koyar:
      // nesne tanımı, dosya başvurusu, grup üyeliği, derleme fazı.
      final result = registerPrivacyManifest(_pbxproj).content;

      String section(String name) {
        final start = result.indexOf('/* Begin $name section */');
        return result.substring(
          start,
          result.indexOf('/* End $name section */'),
        );
      }

      expect(section('PBXBuildFile'), contains('PrivacyInfo.xcprivacy'));
      expect(
        section('PBXFileReference'),
        contains('lastKnownFileType = text.plist.xml'),
      );
      expect(section('PBXGroup'), contains('PrivacyInfo.xcprivacy'));
      expect(
        section('PBXResourcesBuildPhase'),
        contains('PrivacyInfo.xcprivacy in Resources'),
      );
    });

    test('zaten kayıtlıysa ikinci kez eklemez', () {
      final once = registerPrivacyManifest(_pbxproj).content;
      expect(registerPrivacyManifest(once).content, equals(once));
    });

    test('Runner grubu yoksa sorunu bildirir', () {
      final result = registerPrivacyManifest(
        _pbxproj.replaceAll('/* Runner */ = {', '/* Başka */ = {'),
      );

      expect(result.ok, isFalse);
      expect(result.problem, contains('Runner grubu'));
    });
  });

  group('patchAndroidManifest', () {
    test('INTERNET izni, AdMob kimliği ve uygulama adını yazar', () {
      final result = patchAndroidManifest(
        _androidManifest,
        appLabel: 'Denek Uygulaması',
        admobAppId: 'ca-app-pub-1~2',
      );

      expect(result.ok, isTrue);
      expect(result.content, contains('android.permission.INTERNET'));
      expect(result.content, contains('android:label="Denek Uygulaması"'));
      expect(result.content, contains('ca-app-pub-1~2'));
    });

    test('izin <application> ETİKETİNDEN ÖNCE gelir', () {
      // <uses-permission> yalnızca <manifest> altında geçerlidir;
      // <application> içine düşerse Gradle derlemeyi reddeder.
      final content = patchAndroidManifest(
        _androidManifest,
        appLabel: 'Denek',
      ).content;

      expect(
        content.indexOf('uses-permission'),
        lessThan(content.indexOf('<application')),
      );
    });

    test('AdMob kimliği verilmezse meta-data eklenmez', () {
      final content = patchAndroidManifest(
        _androidManifest,
        appLabel: 'Denek',
      ).content;

      expect(content, isNot(contains('gms.ads.APPLICATION_ID')));
    });

    test('iki kez uygulanınca izin yinelenmez', () {
      final once = patchAndroidManifest(
        _androidManifest,
        appLabel: 'Denek',
      ).content;
      final twice = patchAndroidManifest(once, appLabel: 'Denek').content;

      expect('uses-permission'.allMatches(twice), hasLength(1));
    });
  });

  group('patchBuildGradle', () {
    const prelude =
        'val hasReleaseKeystore = rootProject.file("key.properties").exists()';
    const configs =
        '    buildTypes {\n        release {\n            signingConfig = null\n        }\n    }\n';

    test('debug imzalamasını kaldırır', () {
      final result = patchBuildGradle(
        _buildGradle,
        prelude: prelude,
        signingConfigs: configs,
      );

      expect(result.ok, isTrue);
      expect(
        result.content,
        isNot(contains('signingConfigs.getByName("debug")')),
      );
      expect(result.content, contains('key.properties'));
      expect(result.content, contains('import java.util.Properties'));
    });

    test('android bloğunun DIŞINA, önüne yazar', () {
      final content = patchBuildGradle(
        _buildGradle,
        prelude: prelude,
        signingConfigs: configs,
      ).content;

      expect(
        content.indexOf('val hasReleaseKeystore'),
        lessThan(content.indexOf('android {')),
      );
    });

    test('flutter bloğu korunur', () {
      final content = patchBuildGradle(
        _buildGradle,
        prelude: prelude,
        signingConfigs: configs,
      ).content;

      expect(content, contains('source = "../.."'));
    });

    test('zaten yamalıysa dokunmaz', () {
      final once = patchBuildGradle(
        _buildGradle,
        prelude: prelude,
        signingConfigs: configs,
      ).content;

      expect(
        patchBuildGradle(
          once,
          prelude: prelude,
          signingConfigs: configs,
        ).content,
        equals(once),
      );
    });
  });

  group('patchAndroidApplicationId', () {
    test('kts sözdiziminde kimliği değiştirir', () {
      final result = patchAndroidApplicationId(
        '    applicationId = "com.devposs.yazi_tara"\n',
        'com.devposs.yaziTara',
      );

      expect(result.ok, isTrue);
      expect(
        result.content,
        contains('applicationId = "com.devposs.yaziTara"'),
      );
      expect(result.content, isNot(contains('yazi_tara')));
    });

    test('groovy sözdiziminde kimliği değiştirir', () {
      final result = patchAndroidApplicationId(
        "        applicationId 'com.devposs.yazi_tara'\n",
        'com.devposs.yaziTara',
      );

      expect(result.ok, isTrue);
      expect(result.content, contains('applicationId "com.devposs.yaziTara"'));
    });

    test('kimlik zaten aynıysa içerik değişmez', () {
      const gradle = '    applicationId = "com.devposs.yaziTara"\n';

      expect(
        patchAndroidApplicationId(gradle, 'com.devposs.yaziTara').content,
        equals(gradle),
      );
    });

    test('applicationId yoksa sorun bildirir', () {
      final result = patchAndroidApplicationId('android {}\n', 'com.x.y');

      expect(result.ok, isFalse);
      expect(result.content, equals('android {}\n'));
    });
  });

  group('patchPubspec', () {
    const pubspec = '''
name: denek
description: "A new Flutter project."
publish_to: 'none'
version: 1.0.0+1

environment:
  sdk: ^3.10.4
''';

    test('açıklamayı ve sürüm yorumunu yazar', () {
      final result = patchPubspec(
        pubspec,
        description: 'Bir şeyler yapan uygulama.',
        projectName: 'denek',
      );

      expect(result, contains('description: "Bir şeyler yapan uygulama."'));
      expect(result, isNot(contains('A new Flutter project')));
      expect(result, contains('version: 1.0.0+1'));
      expect(result, contains('deploy.sh tarafından'));
    });

    test('ikon ve açılış ekranı yapılandırmasını ekler', () {
      final result = patchPubspec(
        pubspec,
        description: 'x',
        projectName: 'denek',
      );

      expect(result, contains('flutter_launcher_icons:'));
      expect(result, contains('flutter_native_splash:'));
    });

    test('açılış ekranı zemini splash_screen.dart ile aynı: siyah', () {
      final result = patchPubspec(
        pubspec,
        description: 'x',
        projectName: 'denek',
      );
      final splash = result.substring(result.indexOf('flutter_native_splash:'));
      expect(splash, contains('color: "#000000"'));
      expect(splash, isNot(contains('#2F6FED')));
    });

    test('açılış logosu dizinini flutter.assets altına yazar', () {
      const created =
          '$pubspec\n'
          'flutter:\n'
          '  uses-material-design: true\n'
          '\n'
          '  # assets:\n'
          '  #   - images/a_dot_burr.jpeg\n';
      final result = patchPubspec(
        created,
        description: 'x',
        projectName: 'denek',
      );

      expect(result, contains('  assets:\n'));
      expect(result, contains('    - assets/splash/\n'));
      // Beyan flutter: bölümünün içinde, ikon yapılandırmasından ÖNCE olmalı;
      // dosya sonuna düşerse ayrı bir üst düzey anahtar sanılır.
      expect(
        result.indexOf('- assets/splash/'),
        lessThan(result.indexOf('flutter_launcher_icons:')),
      );
      // Yorumdaki örnek assets satırı gerçek liste sanılmamalı.
      expect(result, contains('  # assets:\n'));
    });

    test('var olan assets listesine ekler, ikinci kez eklemez', () {
      const withList =
          'flutter:\n'
          '  uses-material-design: true\n'
          '  assets:\n'
          '    - assets/audio/\n';
      final once = declareSplashAssets(withList);
      expect(once, contains('  assets:\n    # Açılış'));
      expect(once, contains('    - assets/splash/\n    - assets/audio/\n'));
      expect('assets:'.allMatches(once), hasLength(1));
      expect(declareSplashAssets(once), equals(once));
    });

    test('var olan ikon yapılandırmasını ikinci kez eklemez', () {
      final once = patchPubspec(
        pubspec,
        description: 'x',
        projectName: 'denek',
      );
      final twice = patchPubspec(once, description: 'x', projectName: 'denek');

      expect('flutter_launcher_icons:'.allMatches(twice), hasLength(1));
    });
  });

  group('AdMob uygulama kimliği', () {
    const plist =
        '<dict>\n'
        '\t<key>GADApplicationIdentifier</key>\n'
        '\t<string>ca-app-pub-3940256099942544~1458002511</string>\n'
        '</dict>';
    const manifest =
        '    <application android:label="x">\n'
        '        <meta-data\n'
        '            android:name="com.google.android.gms.ads.APPLICATION_ID"\n'
        '            android:value="ca-app-pub-3940256099942544~3347511713" />\n'
        '    </application>';

    test('iOS değerini değiştirir', () {
      final r = setAdmobAppIdIos(plist, 'ca-app-pub-42~99');
      expect(r.ok, isTrue);
      expect(r.content, contains('<string>ca-app-pub-42~99</string>'));
      expect(r.content, isNot(contains('3940256099942544')));
    });

    test('Android değerini değiştirir', () {
      final r = setAdmobAppIdAndroid(manifest, 'ca-app-pub-42~88');
      expect(r.ok, isTrue);
      expect(r.content, contains('android:value="ca-app-pub-42~88"'));
      expect(r.content, isNot(contains('3940256099942544')));
    });

    test('anahtar yoksa problem bildirir', () {
      expect(setAdmobAppIdIos('<dict></dict>', 'x').ok, isFalse);
      expect(
        setAdmobAppIdAndroid('<application></application>', 'x').ok,
        isFalse,
      );
    });

    test('mevcut değeri okur', () {
      expect(
        readAdmobAppIdIos(plist),
        'ca-app-pub-3940256099942544~1458002511',
      );
      expect(
        readAdmobAppIdAndroid(manifest),
        'ca-app-pub-3940256099942544~3347511713',
      );
    });
  });
}

/// Gerçek `flutter create` çıktısında Runner hedefinin üç yapılandırması
/// (Debug/Profile/Release) ve ayrı bir RunnerTests hedefi bulunur.
const _pbxprojWithTargets = '''
/* Begin XCBuildConfiguration section */
		249021D3217E4FDB00AE95B9 /* Profile */ = {
			buildSettings = {
				CURRENT_PROJECT_VERSION = "\$(FLUTTER_BUILD_NUMBER)";
				INFOPLIST_FILE = Runner/Info.plist;
				PRODUCT_BUNDLE_IDENTIFIER = com.ornek.uygulama;
			};
		};
		331C80DB294CC9B700263BE5 /* Debug */ = {
			buildSettings = {
				GENERATE_INFOPLIST_FILE = YES;
				PRODUCT_BUNDLE_IDENTIFIER = com.ornek.uygulama.RunnerTests;
			};
		};
		97C147031CF9000F007C117D /* Debug */ = {
			buildSettings = {
				CURRENT_PROJECT_VERSION = "\$(FLUTTER_BUILD_NUMBER)";
				INFOPLIST_FILE = Runner/Info.plist;
				PRODUCT_BUNDLE_IDENTIFIER = com.ornek.uygulama;
			};
		};
		97C147041CF9000F007C117D /* Release */ = {
			buildSettings = {
				CURRENT_PROJECT_VERSION = "\$(FLUTTER_BUILD_NUMBER)";
				INFOPLIST_FILE = Runner/Info.plist;
				PRODUCT_BUNDLE_IDENTIFIER = com.ornek.uygulama;
			};
		};
/* End XCBuildConfiguration section */
''';

void _developmentTeamTests() {
  group('setDevelopmentTeam', () {
    test('Runner hedefinin her yapılandırmasına takımı yazar', () {
      final result = setDevelopmentTeam(_pbxprojWithTargets, '26BTDFQ8VY');
      expect(result.ok, isTrue);
      expect(
        'DEVELOPMENT_TEAM = 26BTDFQ8VY;'.allMatches(result.content).length,
        3,
        reason: 'Debug, Profile ve Release yapılandırmalarının üçü de',
      );
    });

    test('test hedefine yazmaz', () {
      // RunnerTests\'e takım yazmak imzalamayı bozmaz ama gereksizdir ve
      // hedeflerin ayrı ayarlanabilmesini engeller.
      final result = setDevelopmentTeam(_pbxprojWithTargets, '26BTDFQ8VY');
      final testBlock = result.content.substring(
        result.content.indexOf('331C80DB294CC9B700263BE5'),
        result.content.indexOf('97C147031CF9000F007C117D'),
      );
      expect(testBlock, isNot(contains('DEVELOPMENT_TEAM')));
    });

    test('var olan takıma dokunmaz', () {
      // Bu alan kullanıcının kararı; üzerine yazmak sessizce imzalamayı
      // bozardı.
      final once = setDevelopmentTeam(
        _pbxprojWithTargets,
        'AAAAAAAAAA',
      ).content;
      final twice = setDevelopmentTeam(once, 'BBBBBBBBBB').content;
      expect(twice, once);
      expect(twice, isNot(contains('BBBBBBBBBB')));
    });

    test('boş takım kimliği içeriği değiştirmez', () {
      final result = setDevelopmentTeam(_pbxprojWithTargets, '');
      expect(result.content, _pbxprojWithTargets);
      expect(result.ok, isTrue);
    });

    test('Runner hedefi yoksa sebebini söyler', () {
      final result = setDevelopmentTeam('/* boş proje */', '26BTDFQ8VY');
      expect(result.ok, isFalse);
      expect(result.problem, contains('Runner'));
    });
  });
}
