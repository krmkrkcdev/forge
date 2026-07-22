import 'dart:io';

import 'package:args/command_runner.dart';

import '../checks.dart';
import '../environment.dart';
import '../finding.dart';
import '../project.dart';

/// Bir Flutter projesini mağazaya hazır mı diye denetler.
class DoctorCommand extends Command<int> {
  DoctorCommand() {
    argParser
      ..addOption(
        'path',
        abbr: 'p',
        help: 'Denetlenecek Flutter projesinin yolu.',
        defaultsTo: '.',
      )
      ..addFlag(
        'strict',
        help: 'Uyarıları da hata sayar (CI için).',
        negatable: false,
      );
  }

  @override
  String get name => 'doctor';

  @override
  String get description =>
      'Projeyi App Store ve Play Store yayınına hazır mı diye denetler.';

  @override
  int run() {
    final searchPath = argResults!['path'] as String;
    final project = FlutterProject.locate(searchPath);
    if (project == null) {
      // Aranan yolu yazmak şart: kullanıcı çoğu zaman yanlış dizini verdiğini
      // ancak bunu görünce fark eder.
      stderr.writeln('❌ Flutter projesi bulunamadı: '
          '${Directory(searchPath).absolute.path}');
      stderr.writeln('   Bu dizinde ve üst dizinlerinde pubspec.yaml yok.');
      return 2;
    }

    stdout.writeln('🔎 Denetlenen proje: ${project.appName ?? project.root}');
    stdout.writeln('   ${project.root}\n');

    final findings = runChecks(project);
    final environment = runEnvironmentChecks();

    if (findings.isEmpty && environment.isEmpty) {
      stdout.writeln('✅ Hazır. Yayını engelleyen bir bulgu yok.');
      return 0;
    }

    for (final finding in findings) {
      _print(finding);
    }

    if (environment.isNotEmpty) {
      // Proje kusursuz olsa bile yayın araç zincirinde durabilir; bu yüzden
      // ayrı başlık altında ama aynı çıktının içinde.
      stdout.writeln('── Ortam ${'─' * 55}\n');
      for (final finding in environment) {
        _print(finding);
      }
    }

    final all = [...findings, ...environment];
    final blockers = all.where((f) => f.severity == Severity.blocker).length;
    final warnings = all.where((f) => f.severity == Severity.warning).length;
    final autoFixable = all.where((f) => f.autoFixable).length;

    stdout.writeln('─' * 64);
    stdout.writeln('$blockers engel, $warnings uyarı, '
        '${all.length - blockers - warnings} bilgi.');
    if (autoFixable > 0) {
      stdout.writeln('$autoFixable tanesi otomatik düzeltilebilir:  forge fix');
    }

    final strict = argResults!['strict'] as bool;
    if (blockers > 0) return 1;
    if (strict && warnings > 0) return 1;
    return 0;
  }

  void _print(Finding f) {
    final icon = switch (f.severity) {
      Severity.blocker => '⛔',
      Severity.warning => '⚠️ ',
      Severity.info => 'ℹ️ ',
    };
    final platform = switch (f.platform) {
      Platform.ios => 'iOS',
      Platform.android => 'Android',
      Platform.both => 'iOS+Android',
    };

    stdout.writeln('$icon [${f.severity.label}] $platform — ${f.title}');
    stdout.writeln('   Neden: ${_wrap(f.why)}');
    stdout.writeln('   Çözüm: ${_wrap(f.fix)}');
    if (f.autoFixable) stdout.writeln('   (forge fix bunu düzeltebilir)');
    stdout.writeln('');
  }

  /// Uzun metni terminalde okunur tutar.
  ///
  /// Metindeki satır sonları korunur: çözüm metinleri çoğu zaman kopyalanacak
  /// kod parçası içeriyor ve o satırların bütünlüğü bozulmamalı.
  static String _wrap(String text, {int width = 72, String indent = '          '}) {
    final lines = <String>[];

    for (final paragraph in text.split('\n')) {
      // Kod satırlarının girintisi anlam taşır; sarmadan aynen aktarılır.
      if (paragraph.startsWith(' ')) {
        lines.add(paragraph);
        continue;
      }

      final buffer = StringBuffer();
      var lineLength = 0;
      for (final word in paragraph.split(' ').where((w) => w.isNotEmpty)) {
        if (lineLength > 0 && lineLength + word.length > width) {
          lines.add(buffer.toString());
          buffer.clear();
          lineLength = 0;
        }
        if (lineLength > 0) {
          buffer.write(' ');
          lineLength++;
        }
        buffer.write(word);
        lineLength += word.length;
      }
      lines.add(buffer.toString());
    }

    return lines.join('\n$indent');
  }
}
