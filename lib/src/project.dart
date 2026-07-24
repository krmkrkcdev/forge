import 'dart:io';

import 'package:path/path.dart' as p;

/// Denetlenen Flutter projesine erişim.
///
/// Dosya okumaları tek yerde toplanır ki denetim kuralları "dosya var mı,
/// okunabildi mi" ayrıntısıyla uğraşmasın.
class FlutterProject {
  FlutterProject(this.root);

  final String root;

  /// Verilen dizinden yukarı doğru pubspec.yaml arar.
  ///
  /// Kullanıcının `app/` alt klasöründen ya da kökten çalıştırması aynı
  /// sonucu vermeli.
  static FlutterProject? locate(String startDir) {
    var dir = Directory(p.absolute(startDir));
    while (true) {
      if (File(p.join(dir.path, 'pubspec.yaml')).existsSync()) {
        return FlutterProject(dir.path);
      }
      final parent = dir.parent;
      if (parent.path == dir.path) return null;
      dir = parent;
    }
  }

  String path(String relative) => p.join(root, relative);

  bool exists(String relative) =>
      File(path(relative)).existsSync() || Directory(path(relative)).existsSync();

  /// Dosya içeriği; yoksa `null`.
  String? read(String relative) {
    final file = File(path(relative));
    if (!file.existsSync()) return null;
    try {
      return file.readAsStringSync();
    } on FileSystemException {
      return null;
    }
  }

  bool contains(String relative, Pattern needle) {
    final content = read(relative);
    return content != null && content.contains(needle);
  }

  bool get hasAndroid => exists('android');
  bool get hasIos => exists('ios');

  /// Uygulama kaynağında (lib/) geçen bir metin var mı?
  ///
  /// Bazı kurallar dosyanın değil, KODUN bir şey yapıp yapmadığına bakar —
  /// örneğin kullanıcı onayının hiç istenmemesi. Kaba bir ölçüt olduğu için
  /// yalnızca uyarı üretmekte kullanılır.
  bool libContains(Pattern needle) {
    final dir = Directory(path('lib'));
    if (!dir.existsSync()) return false;
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      try {
        if (entity.readAsStringSync().contains(needle)) return true;
      } on FileSystemException {
        continue;
      }
    }
    return false;
  }

  /// Uygulama reklam gösteriyor mu?
  bool get usesAds => (pubspec ?? '').contains('google_mobile_ads:');

  String get pubspecPath => 'pubspec.yaml';
  String? get pubspec => read(pubspecPath);

  /// `version:` satırındaki ham değer (ör. `1.0.0+3`).
  String? get versionValue {
    final content = pubspec;
    if (content == null) return null;
    final match = RegExp(r'^version:\s*(.+?)\s*(#.*)?$', multiLine: true)
        .firstMatch(content);
    return match?.group(1)?.trim();
  }

  String? get appName {
    final content = pubspec;
    if (content == null) return null;
    return RegExp(r'^name:\s*(\S+)', multiLine: true).firstMatch(content)?.group(1);
  }

  /// Android `applicationId`.
  String? get androidApplicationId {
    for (final f in ['android/app/build.gradle.kts', 'android/app/build.gradle']) {
      final content = read(f);
      if (content == null) continue;
      final match = RegExp(r'''applicationId\s*=?\s*["']([^"']+)["']''')
          .firstMatch(content);
      if (match != null) return match.group(1);
    }
    return null;
  }

  /// iOS `PRODUCT_BUNDLE_IDENTIFIER` (test hedefleri hariç).
  String? get iosBundleId {
    final content = read('ios/Runner.xcodeproj/project.pbxproj');
    if (content == null) return null;
    for (final match
        in RegExp(r'PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);').allMatches(content)) {
      final value = match.group(1)!.trim();
      if (!value.endsWith('.RunnerTests')) return value;
    }
    return null;
  }

  /// Uygulamanın ana Android manifesti.
  String? get androidManifest => read('android/app/src/main/AndroidManifest.xml');

  String? get iosInfoPlist => read('ios/Runner/Info.plist');
}
