import 'dart:io';

import 'package:args/command_runner.dart';

import '../checks.dart';
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
    final project = FlutterProject.locate(argResults!['path'] as String);
    if (project == null) {
      stderr.writeln('❌ Flutter projesi bulunamadı (pubspec.yaml yok).');
      return 2;
    }

    stdout.writeln('🔎 Denetlenen proje: ${project.appName ?? project.root}');
    stdout.writeln('   ${project.root}\n');

    final findings = runChecks(project);

    if (findings.isEmpty) {
      stdout.writeln('✅ Hazır. Yayını engelleyen bir bulgu yok.');
      return 0;
    }

    for (final finding in findings) {
      _print(finding);
    }

    final blockers = findings.where((f) => f.severity == Severity.blocker).length;
    final warnings = findings.where((f) => f.severity == Severity.warning).length;
    final autoFixable = findings.where((f) => f.autoFixable).length;

    stdout.writeln('─' * 64);
    stdout.writeln('$blockers engel, $warnings uyarı, '
        '${findings.length - blockers - warnings} bilgi.');
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
  static String _wrap(String text, {int width = 72, String indent = '          '}) {
    final words = text.replaceAll('\n', '\n ').split(' ');
    final buffer = StringBuffer();
    var lineLength = 0;
    for (final word in words) {
      if (word.contains('\n')) {
        buffer.write('\n$indent${word.replaceAll('\n', '')}');
        lineLength = word.length;
        continue;
      }
      if (lineLength + word.length > width) {
        buffer.write('\n$indent');
        lineLength = 0;
      }
      buffer.write('$word ');
      lineLength += word.length + 1;
    }
    return buffer.toString().trimRight();
  }
}
