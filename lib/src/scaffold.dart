import 'dart:io';

import 'package:path/path.dart' as p;

import 'templates/bundle.dart';

/// Şablon dosyalarını hedefe yazan, yerleştirmeyi bilen katman.
///
/// `forge new` komutunun kendisi akışı anlatır; dosya sistemine dokunan her
/// şey burada toplanır ki komut okunduğunda ne olduğu tek bakışta anlaşılsın.
class ProjectScaffold {
  ProjectScaffold({
    required this.root,
    required this.appDir,
    required this.substitutions,
    required this.log,
  });

  /// Depo kökü — AGENTS.md ve .gitignore buraya gelir.
  final String root;

  /// Flutter projesinin dizini (genellikle `<root>/app`).
  final String appDir;

  /// `{{ANAHTAR}}` → değer.
  final Map<String, String> substitutions;

  final void Function(String message) log;

  /// Şablon yolu → hedef yol. Hedef, `<root>` göreli.
  ///
  /// Eşleme bilinçli olarak açıkça yazılmıştır: adlandırma kuralına
  /// dayansaydı, şablona yeni bir dosya eklendiğinde nereye gideceğini
  /// kestirmek gerekirdi.
  Map<String, String> get fileMap => {
        'AGENTS.md': 'AGENTS.md',
        'docs/REKLAM.md': 'docs/REKLAM.md',
        'deploy.sh': '$_app/deploy.sh',
        'Gemfile': '$_app/Gemfile',
        'env.example': '$_app/.env.example',
        'android/key.properties.example': '$_app/android/key.properties.example',
        'android/fastlane/Appfile': '$_app/android/fastlane/Appfile',
        'android/fastlane/Fastfile': '$_app/android/fastlane/Fastfile',
        'android/fastlane/release_notes.txt.example':
            '$_app/android/fastlane/release_notes.txt.example',
        'ios/fastlane/Appfile': '$_app/ios/fastlane/Appfile',
        'ios/fastlane/Fastfile': '$_app/ios/fastlane/Fastfile',
        'ios/fastlane/Matchfile': '$_app/ios/fastlane/Matchfile',
        'ios/fastlane/release_notes.txt.example':
            '$_app/ios/fastlane/release_notes.txt.example',
        'ios/PrivacyInfo.xcprivacy': '$_app/ios/Runner/PrivacyInfo.xcprivacy',
        'lib/main.dart': '$_app/lib/main.dart',
        'lib/theme/app_theme.dart': '$_app/lib/theme/app_theme.dart',
        'lib/screens/home_screen.dart': '$_app/lib/screens/home_screen.dart',
        'lib/services/ad_service.dart': '$_app/lib/services/ad_service.dart',
        'lib/widgets/banner_ad_slot.dart': '$_app/lib/widgets/banner_ad_slot.dart',
      };

  /// Bu dosyalar kopyalanmaz; başka bir dosyanın içine karıştırılır.
  static const spliced = {
    'gitignore_additions',
    'ios/info_additions.plist',
    'android/signing.gradle.kts',
    'android/signing_configs.gradle.kts',
  };

  String get _app => p.relative(appDir, from: root);

  /// Şablondaki `{{ANAHTAR}}` yer tutucularını doldurur.
  String render(String templatePath) {
    var content = templateFile(templatePath);
    if (content == null) {
      throw StateError('Şablon bulunamadı: $templatePath. '
          'dart run tool/bundle_assets.dart çalıştırıldı mı?');
    }
    substitutions.forEach((key, value) {
      content = content!.replaceAll('{{$key}}', value);
    });
    return content!;
  }

  /// Bütün şablon dosyalarını yerine yazar.
  void copyAll() {
    fileMap.forEach((source, target) {
      write(target, render(source));
    });
    // deploy.sh çalıştırılabilir olmalı; kopyalama izinleri taşımaz.
    _makeExecutable(p.join(root, '$_app/deploy.sh'));
  }

  void write(String relativeTarget, String content) {
    final file = File(p.join(root, relativeTarget));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
    log('  yazıldı  $relativeTarget');
  }

  /// Var olan bir dosyanın sonuna ekler.
  void append(String relativeTarget, String content) {
    final file = File(p.join(root, relativeTarget));
    file.parent.createSync(recursive: true);
    final existing = file.existsSync() ? file.readAsStringSync() : '';
    final separator =
        existing.isEmpty || existing.endsWith('\n') ? '' : '\n';
    file.writeAsStringSync('$existing$separator$content');
    log('  eklendi  $relativeTarget');
  }

  void _makeExecutable(String path) {
    if (Platform.isWindows) return;
    Process.runSync('chmod', ['+x', path]);
  }
}
