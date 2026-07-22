import 'dart:io';

import 'package:args/command_runner.dart';

import '../checks.dart';
import '../project.dart';

/// Güvenle otomatikleştirilebilen düzeltmeleri uygular.
///
/// Bilinçli olarak dar tutulmuştur: yalnızca tek doğru cevabı olan ve
/// kullanıcının kararını gerektirmeyen düzeltmeler burada. İmzalama anahtarı
/// üretmek, paket kimliği seçmek gibi kararlar kullanıcıya aittir.
class FixCommand extends Command<int> {
  FixCommand() {
    argParser
      ..addOption('path', abbr: 'p', defaultsTo: '.')
      ..addFlag('dry-run',
          help: 'Neyin değişeceğini gösterir, dosyaya yazmaz.',
          negatable: false);
  }

  @override
  String get name => 'fix';

  @override
  String get description => 'Otomatik düzeltilebilen bulguları giderir.';

  @override
  int run() {
    final project = FlutterProject.locate(argResults!['path'] as String);
    if (project == null) {
      stderr.writeln('❌ Flutter projesi bulunamadı.');
      return 2;
    }
    final dryRun = argResults!['dry-run'] as bool;

    final applied = <String>[];
    for (final finding in runChecks(project)) {
      if (!finding.autoFixable) continue;
      final result = _apply(project, finding.id, dryRun);
      if (result != null) applied.add(result);
    }

    if (applied.isEmpty) {
      stdout.writeln('Otomatik düzeltilecek bir şey yok.');
      return 0;
    }

    for (final line in applied) {
      stdout.writeln('${dryRun ? "· " : "✔ "}$line');
    }
    if (dryRun) {
      stdout.writeln('\n(deneme çalıştırması — hiçbir dosya değişmedi)');
    } else {
      stdout.writeln('\n${applied.length} düzeltme uygulandı. '
          'Kontrol için:  forge doctor');
    }
    return 0;
  }

  String? _apply(FlutterProject project, String id, bool dryRun) {
    switch (id) {
      case 'version-no-build-number':
      case 'version-missing':
        return _fixVersion(project, dryRun);
      case 'ios-export-compliance':
        return _fixExportCompliance(project, dryRun);
      case 'android-internet-permission':
        return _fixInternetPermission(project, dryRun);
      case 'secrets-not-ignored':
        return _fixSecretsIgnore(project, dryRun);
      default:
        return null;
    }
  }

  String? _fixVersion(FlutterProject project, bool dryRun) {
    final file = File(project.path('pubspec.yaml'));
    final content = file.readAsStringSync();
    final current = project.versionValue;

    final String updated;
    if (current == null) {
      updated = content.replaceFirst(
        RegExp(r'^(name:.*)$', multiLine: true),
        r'$1' '\nversion: 1.0.0+1',
      );
    } else {
      updated = content.replaceFirst(
        RegExp(r'^version:\s*.+$', multiLine: true),
        'version: $current+1',
      );
    }

    if (!dryRun) file.writeAsStringSync(updated);
    return 'pubspec.yaml sürümüne build numarası eklendi '
        '(${current ?? "yok"} → ${current ?? "1.0.0"}+1)';
  }

  String? _fixExportCompliance(FlutterProject project, bool dryRun) {
    final file = File(project.path('ios/Runner/Info.plist'));
    if (!file.existsSync()) return null;
    final content = file.readAsStringSync();

    // Son </dict></plist> kapanışından hemen önce ekle.
    final index = content.lastIndexOf('</dict>');
    if (index == -1) return null;

    const entry = '\t<key>ITSAppUsesNonExemptEncryption</key>\n\t<false/>\n';
    final updated = content.replaceRange(index, index, entry);

    if (!dryRun) file.writeAsStringSync(updated);
    return 'Info.plist içine ITSAppUsesNonExemptEncryption=false eklendi';
  }

  /// Eksik sır desenlerini projenin .gitignore dosyasına ekler.
  ///
  /// Deponun kökündeki .gitignore'a değil, projenin kendi dizinindekine
  /// yazıyoruz: git iç içe .gitignore dosyalarına saygı duyar ve forge'un
  /// denetlediği sınırın dışına çıkmamak gerekir.
  String? _fixSecretsIgnore(FlutterProject project, bool dryRun) {
    final missing = unprotectedSecrets(project);
    if (missing == null || missing.isEmpty) return null;

    final file = File(project.path('.gitignore'));
    final existing = file.existsSync() ? file.readAsStringSync() : '';
    final patterns = missing.map((k) => k.pattern).toSet().toList();

    final buffer = StringBuffer(existing);
    if (existing.isNotEmpty && !existing.endsWith('\n')) buffer.write('\n');
    buffer.write('\n# Sırlar — asla depoya girmemeli (forge fix)\n');
    for (final pattern in patterns) {
      buffer.writeln(pattern);
    }

    if (!dryRun) file.writeAsStringSync(buffer.toString());
    return '.gitignore içine ${patterns.length} sır deseni eklendi '
        '(${patterns.join(", ")})';
  }

  String? _fixInternetPermission(FlutterProject project, bool dryRun) {
    final file = File(project.path('android/app/src/main/AndroidManifest.xml'));
    if (!file.existsSync()) return null;
    final content = file.readAsStringSync();
    if (content.contains('android.permission.INTERNET')) return null;

    final index = content.indexOf('<application');
    if (index == -1) return null;

    const entry =
        '    <uses-permission android:name="android.permission.INTERNET"/>\n\n';
    final updated = content.replaceRange(index, index, entry);

    if (!dryRun) file.writeAsStringSync(updated);
    return 'AndroidManifest.xml içine INTERNET izni eklendi';
  }
}
