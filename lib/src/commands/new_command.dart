import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../native_patch.dart';
import '../project.dart';
import '../scaffold.dart';


/// Yeni bir uygulamayı standartlarla başlatır.
///
/// `flutter create` iyi bir başlangıç noktası üretir ama mağazaya hazır bir
/// proje üretmez: imzalama debug anahtarındadır, ana manifestte INTERNET izni
/// yoktur, gizlilik manifesti yoktur, yayın akışı yoktur. Bu komut aradaki
/// farkı kapatır — yani `forge doctor`un daha ilk günden temiz çıktığı bir
/// proje bırakır.
class NewCommand extends Command<int> {
  NewCommand() {
    argParser
      ..addOption(
        'org',
        abbr: 'o',
        help: 'Ters alan adı. Paket kimliği bundan türetilir '
            've YAYINLANDIKTAN SONRA DEĞİŞTİRİLEMEZ.',
        valueHelp: 'com.sirketiniz',
      )
      ..addOption(
        'app-name',
        help: 'Kullanıcının gördüğü ad. Verilmezse proje adından türetilir.',
        valueHelp: 'Uygulama Adı',
      )
      ..addOption(
        'description',
        help: 'Bir cümlelik açıklama.',
      )
      ..addOption(
        'path',
        abbr: 'p',
        help: 'Projenin oluşturulacağı dizin. Varsayılan: ./<ad>',
      )
      ..addFlag(
        'git',
        help: 'Depoyu başlatır ve ilk commit\'i atar.',
        defaultsTo: true,
      )
      ..addFlag(
        'pub-add',
        help: 'Bağımlılıkları flutter pub add ile ekler (ağ gerektirir).',
        defaultsTo: true,
      )
      ..addFlag(
        'backend',
        help: 'FastAPI + PostgreSQL + Docker sunucu katmanını (backend/) '
            'üretir. Çevrimdışı öncelikli senkron iskeleti.',
        defaultsTo: false,
      );
  }

  @override
  String get name => 'new';

  @override
  String get description => 'Mağazaya hazır yeni bir Flutter projesi üretir.';

  @override
  String get invocation => 'forge new <proje_adi> --org com.sirketiniz';

  /// Uygulama koduna eklenen paketler.
  ///
  /// Reklam katmanı google_mobile_ads'e, arayüz metinleri intl'e bağlı.
  /// shared_preferences neredeyse her uygulamada gerekiyor ve gizlilik
  /// manifestindeki UserDefaults gerekçesi onun için yazıldı.
  static const _dependencies = [
    'google_mobile_ads',
    'intl',
    'shared_preferences',
  ];

  static const _devDependencies = [
    'flutter_launcher_icons',
    'flutter_native_splash',
  ];

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.isEmpty) {
      return _fail('Proje adı verilmedi.\n\n  $invocation');
    }
    final projectName = rest.first;
    final nameProblem = _validateProjectName(projectName);
    if (nameProblem != null) return _fail(nameProblem);

    final org = argResults!['org'] as String?;
    if (org == null) {
      return _fail(
        'Ters alan adı (--org) zorunlu.\n\n'
        'Paket kimliği bundan türetilir ve uygulama yayınlandıktan sonra '
        'DEĞİŞTİRİLEMEZ. Varsayılan bir değer koymuyoruz çünkü yanlış '
        'kimlikle yayınlanan uygulama geri alınamaz.\n\n'
        '  $invocation',
      );
    }
    final orgProblem = _validateOrg(org);
    if (orgProblem != null) return _fail(orgProblem);

    final appName = (argResults!['app-name'] as String?) ?? _titleCase(projectName);
    final description = (argResults!['description'] as String?) ??
        '$appName uygulaması.';

    final root = p.absolute((argResults!['path'] as String?) ?? projectName);
    final appDir = p.join(root, 'app');

    if (Directory(root).existsSync() &&
        Directory(root).listSync().isNotEmpty) {
      return _fail('Dizin zaten dolu: $root\n'
          'Var olan bir projenin üzerine yazmıyoruz.');
    }

    stdout.writeln('🔨 $appName oluşturuluyor');
    stdout.writeln('   $root\n');

    // 1 ---------------------------------------------------- flutter create
    final created = _flutterCreate(
      appDir: appDir,
      projectName: projectName,
      org: org,
      description: description,
    );
    if (created != 0) return created;

    final project = FlutterProject(appDir);

    // Alt çizgili proje adlarında flutter create iki mağazaya farklı kimlik
    // üretir; Android, iOS'un kimliğine eşitlenir (bkz.
    // patchAndroidApplicationId). packageId bu satırdan SONRA okunmalı ki
    // şablonlara ortak kimlik gitsin.
    final iosId = project.iosBundleId;
    if (iosId != null &&
        project.androidApplicationId != null &&
        project.androidApplicationId != iosId) {
      for (final rel in [
        'android/app/build.gradle.kts',
        'android/app/build.gradle',
      ]) {
        final file = File(p.join(appDir, rel));
        if (!file.existsSync()) continue;
        final patched =
            patchAndroidApplicationId(file.readAsStringSync(), iosId);
        if (patched.ok) {
          file.writeAsStringSync(patched.content);
          stdout.writeln('  eşitlendi   $rel → applicationId = $iosId');
        }
        break;
      }
    }

    final packageId = project.androidApplicationId ?? '$org.$projectName';

    // 2 ------------------------------------------------------- şablon katmanı
    stdout.writeln('\n📦 Standart katman uygulanıyor');
    final scaffold = ProjectScaffold(
      root: root,
      appDir: appDir,
      log: stdout.writeln,
      substitutions: {
        'APP_NAME': appName,
        'APP_CLASS': '${_pascalCase(projectName)}App',
        'PROJECT_NAME': projectName,
        'PACKAGE_ID': packageId,
        'DESCRIPTION': description,
        // Google'ın test uygulama kimlikleri. Gerçekleriyle değiştirmek
        // bilinçli bir adım olmalı; forge doctor unutulursa uyarır.
        'ADMOB_APP_ID_IOS': 'ca-app-pub-3940256099942544~1458002511',
        'ADMOB_APP_ID_ANDROID': 'ca-app-pub-3940256099942544~3347511713',
      },
    );
    scaffold.copyAll();
    scaffold.append('.gitignore', scaffold.render('gitignore_additions'));

    // İsteğe bağlı sunucu katmanı (backend/ + app tarafı sözleşme testi).
    final withBackend = argResults!['backend'] as bool;
    if (withBackend) {
      stdout.writeln('\n🐍 Backend katmanı (FastAPI + PostgreSQL)');
      scaffold.copyBackend();
    }

    // flutter create'in ürettiği örnek testler silinen widget'lara bakıyor.
    _remove(p.join(appDir, 'test', 'widget_test.dart'));

    // 3 -------------------------------------------------------- yerel yamalar
    stdout.writeln('\n🩹 Yerel proje dosyaları düzeltiliyor');
    final problems = <String>[];

    _patchFile(
      p.join(appDir, 'ios/Runner/Info.plist'),
      (content) => patchInfoPlist(content, scaffold.render('ios/info_additions.plist')),
      label: 'ios/Runner/Info.plist',
      problems: problems,
    );
    _patchFile(
      p.join(appDir, 'ios/Runner.xcodeproj/project.pbxproj'),
      registerPrivacyManifest,
      label: 'ios/Runner.xcodeproj (PrivacyInfo kaydı)',
      problems: problems,
    );
    _patchFile(
      p.join(appDir, 'android/app/src/main/AndroidManifest.xml'),
      (content) => patchAndroidManifest(
        content,
        appLabel: appName,
        admobAppId: scaffold.substitutions['ADMOB_APP_ID_ANDROID'],
      ),
      label: 'android/app/src/main/AndroidManifest.xml',
      problems: problems,
    );
    _patchFile(
      p.join(appDir, 'android/app/build.gradle.kts'),
      (content) => patchBuildGradle(
        content,
        prelude: scaffold.render('android/signing.gradle.kts'),
        signingConfigs: scaffold.render('android/signing_configs.gradle.kts'),
      ),
      label: 'android/app/build.gradle.kts',
      problems: problems,
    );

    final pubspecFile = File(p.join(appDir, 'pubspec.yaml'));
    pubspecFile.writeAsStringSync(patchPubspec(
      pubspecFile.readAsStringSync(),
      description: description,
      projectName: projectName,
    ));
    stdout.writeln('  düzeltildi  pubspec.yaml');

    Directory(p.join(appDir, 'assets/icon')).createSync(recursive: true);

    // 4 ------------------------------------------------------- bağımlılıklar
    if (argResults!['pub-add'] as bool) {
      stdout.writeln('\n📚 Bağımlılıklar ekleniyor');
      _pubAdd(appDir, problems);
    }

    // 5 ---------------------------------------------------------------- git
    if (argResults!['git'] as bool) {
      _gitInit(root);
    }

    _printNextSteps(
      root: root,
      appName: appName,
      packageId: packageId,
      problems: problems,
      backend: withBackend,
    );
    return problems.isEmpty ? 0 : 1;
  }

  // ------------------------------------------------------------- adımlar

  int _flutterCreate({
    required String appDir,
    required String projectName,
    required String org,
    required String description,
  }) {
    stdout.writeln('▶ flutter create');
    final result = Process.runSync('flutter', [
      'create',
      '--project-name', projectName,
      '--org', org,
      '--description', description,
      '--platforms', 'ios,android',
      appDir,
    ]);
    if (result.exitCode != 0) {
      stderr.writeln(result.stdout);
      stderr.writeln(result.stderr);
      // Flutter yoksa hata mesajı "command not found" olur ve kullanıcı
      // forge'u suçlar; sebebi açıkça söylüyoruz.
      stderr.writeln('\n❌ flutter create başarısız oldu. '
          'Flutter kurulu ve PATH\'te mi?  flutter --version');
      return 1;
    }
    return 0;
  }

  void _pubAdd(String appDir, List<String> problems) {
    // Sıra önemli: flutter_localizations, Flutter SDK'sının içindeki intl
    // sürümünü sabitler. Önce intl eklenirse pub en güncel sürümü seçer ve
    // sonraki adımda "version solving failed" ile durur.
    final batches = <List<String>>[
      ['pub', 'add', '--sdk=flutter', 'flutter_localizations'],
      ['pub', 'add', ..._dependencies],
      ['pub', 'add', ..._devDependencies.map((d) => 'dev:$d')],
    ];

    for (final args in batches) {
      final result = Process.runSync('flutter', args, workingDirectory: appDir);
      if (result.exitCode != 0) {
        stderr.writeln(result.stderr);
        problems.add('Bağımlılıklar eklenemedi (${args.skip(2).join(", ")}). '
            'Ağ bağlantısını kontrol edip elle çalıştırın:\n'
            '  cd ${p.relative(appDir)} && flutter ${args.join(" ")}');
        return;
      }
    }
    stdout.writeln('  eklendi  ${_dependencies.join(", ")}, '
        'flutter_localizations');
    stdout.writeln('  eklendi  ${_devDependencies.join(", ")} (geliştirme)');
  }

  void _gitInit(String root) {
    stdout.writeln('\n🌱 git deposu başlatılıyor');
    final init = Process.runSync('git', ['init', '-q'], workingDirectory: root);
    if (init.exitCode != 0) {
      stdout.writeln('  atlandı (git çalıştırılamadı)');
      return;
    }
    Process.runSync('git', ['add', '.'], workingDirectory: root);
    Process.runSync(
      'git',
      ['commit', '-q', '-m', 'forge new: magazaya hazir iskelet'],
      workingDirectory: root,
    );
    stdout.writeln('  ilk commit atıldı');
  }

  // ------------------------------------------------------------- yardımcılar

  void _patchFile(
    String path,
    PatchResult Function(String content) patch, {
    required String label,
    required List<String> problems,
  }) {
    final file = File(path);
    if (!file.existsSync()) {
      problems.add('$label bulunamadı; yama uygulanamadı.');
      return;
    }
    final result = patch(file.readAsStringSync());
    if (!result.ok) {
      problems.add('$label: ${result.problem}');
      return;
    }
    file.writeAsStringSync(result.content);
    stdout.writeln('  düzeltildi  $label');
  }

  void _remove(String path) {
    final file = File(path);
    if (file.existsSync()) file.deleteSync();
  }

  int _fail(String message) {
    stderr.writeln('❌ $message');
    return 64;
  }

  /// Dart paket adı kuralları. `flutter create` de denetler ama hatası
  /// dizin oluşturulduktan sonra gelir.
  static String? _validateProjectName(String name) {
    if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(name)) {
      return 'Geçersiz proje adı: "$name"\n'
          'Küçük harfle başlamalı; yalnızca küçük harf, rakam ve alt çizgi '
          'içerebilir (ör. not_defteri).';
    }
    const reserved = {'test', 'flutter', 'dart', 'app'};
    if (reserved.contains(name)) {
      return '"$name" ayrılmış bir addır; başka bir ad seçin.';
    }
    return null;
  }

  static String? _validateOrg(String org) {
    if (!RegExp(r'^[a-z][a-z0-9]*(\.[a-z][a-z0-9]*)+$').hasMatch(org)) {
      return 'Geçersiz --org: "$org"\n'
          'Ters alan adı biçiminde olmalı (ör. com.sirketiniz).';
    }
    if (org.startsWith('com.example')) {
      return '--org olarak "com.example" kullanılamaz.\n'
          'Apple ve Google bu kimlikle başlayan uygulamayı kabul etmez.';
    }
    return null;
  }

  static String _titleCase(String snake) => snake
      .split('_')
      .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
      .join(' ');

  static String _pascalCase(String snake) => snake
      .split('_')
      .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
      .join();

  void _printNextSteps({
    required String root,
    required String appName,
    required String packageId,
    required List<String> problems,
    bool backend = false,
  }) {
    final rel = p.relative(root);

    if (problems.isNotEmpty) {
      stdout.writeln('\n${'─' * 64}');
      stdout.writeln('⚠️  Proje oluşturuldu ama bazı adımlar elle '
          'tamamlanmalı:\n');
      for (final problem in problems) {
        stdout.writeln('  • $problem');
      }
    }

    stdout.writeln('\n${'─' * 64}');
    stdout.writeln('✅ $appName hazır.  ($packageId)\n');
    stdout.writeln('Çalıştırmak için:');
    stdout.writeln('  cd $rel/app && flutter run\n');
    stdout.writeln('Yayına giden yol — sırayla:\n');
    stdout.writeln('  1. İkon: assets/icon/icon.png (1024x1024, saydamsız) ve');
    stdout.writeln('     icon_foreground.png koyun, sonra:');
    stdout.writeln('       dart run flutter_launcher_icons');
    stdout.writeln('       dart run flutter_native_splash:create');
    stdout.writeln('  2. İmzalama: android/key.properties.example → '
        'key.properties');
    stdout.writeln('     ve Xcode\'da Runner → Signing & Capabilities → Team');
    stdout.writeln('  3. Reklam: AdMob konsolunda uygulamayı açın.');
    stdout.writeln('     • uygulama kimliğini (~ işaretli) Info.plist ve');
    stdout.writeln('       AndroidManifest.xml içine yazın');
    stdout.writeln('     • birim kimliklerini (/ işaretli) .env dosyasına');
    stdout.writeln('     • Privacy & messaging → GDPR mesajını yayınlayın');
    stdout.writeln('     Ayrıntı: docs/REKLAM.md');
    stdout.writeln('  4. Yayın: .env.example → .env, doldurun');
    stdout.writeln('  5. Denetim:  forge doctor --path $rel/app');
    stdout.writeln('  6. Deneme:   ./deploy.sh ios beta --dry-run');

    if (backend) {
      stdout.writeln('\nBackend (FastAPI + PostgreSQL):');
      stdout.writeln('  cd $rel/backend && docker compose up --build');
      stdout.writeln('  → API http://localhost:8000  ·  dokümanlar /docs');
      stdout.writeln('  Uygulamaya API adresini panelden (Yapılandırma → '
          'API taban adresi) ya da .env\'e yaz.');
    }
  }
}
