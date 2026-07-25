import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../project.dart';

/// Tek bir görselden uygulama ikonu ve açılış ekranı üretir.
///
/// `flutter_launcher_icons` ve `flutter_native_splash` her forge projesinde
/// zaten kuruludur ve pubspec'te yapılandırması vardır (bkz. patchPubspec).
/// Bu komut yalnızca görseli doğru yere koyar ve iki aracı sırayla çalıştırır
/// — her uygulamada tekrarlanan elle adımı ortadan kaldırır.
class IconCommand extends Command<int> {
  IconCommand() {
    argParser
      ..addOption('path',
          abbr: 'p',
          help: 'Proje dizini. Verilmezse bulunulan yerden yukarı aranır.')
      ..addOption('foreground',
          help: 'Adaptive (Android) ikon ön planı. Verilmezse ana görsel '
              'kullanılır.')
      ..addFlag('splash',
          defaultsTo: true, help: 'Açılış ekranını da üretir.');
  }

  @override
  String get name => 'icon';

  @override
  String get description =>
      'Tek görselden uygulama ikonu ve açılış ekranı üretir.';

  @override
  String get invocation => 'forge icon <gorsel.png> [--path app]';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.isEmpty) {
      return _fail('Görsel verilmedi.\n\n  $invocation');
    }
    final imagePath = p.absolute(rest.first);
    final image = File(imagePath);
    if (!image.existsSync()) {
      return _fail('Görsel bulunamadı: $imagePath');
    }

    final start = (argResults!['path'] as String?) ?? Directory.current.path;
    final project = FlutterProject.locate(start);
    if (project == null) {
      return _fail('Flutter projesi bulunamadı: $start\n'
          'Proje dizinini --path ile verin.');
    }

    // 1024x1024 ve saydamsız olmalı — App Store saydam ikonu reddeder. macOS'ta
    // sips ile ucuz bir uyarı verebiliyoruz; başka yerde sessizce geçiyoruz.
    _warnIfNotSquare1024(imagePath);

    // 1 ------------------------------------------------- görseli yerine koy
    final iconDir = Directory(p.join(project.root, 'assets', 'icon'))
      ..createSync(recursive: true);
    image.copySync(p.join(iconDir.path, 'icon.png'));
    final fgPath = argResults!['foreground'] as String?;
    File(fgPath != null ? p.absolute(fgPath) : imagePath)
        .copySync(p.join(iconDir.path, 'icon_foreground.png'));
    stdout.writeln('🖼  görsel kopyalandı → assets/icon/'
        '${fgPath == null ? '  (ikon + adaptive ön plan aynı görsel)' : ''}');

    // 2 ----------------------------------------------------- araçları çalıştır
    final iconsOk = _run(
      project.root,
      ['run', 'flutter_launcher_icons'],
      'Uygulama ikonu üretiliyor',
    );
    if (!iconsOk) {
      return _fail('flutter_launcher_icons başarısız. Bağımlılıklar kurulu mu? '
          '(cd ${p.relative(project.root)} && flutter pub get)');
    }

    if (argResults!['splash'] as bool) {
      final splashOk = _run(
        project.root,
        ['run', 'flutter_native_splash:create'],
        'Açılış ekranı üretiliyor',
      );
      if (!splashOk) {
        stdout.writeln('⚠️  Açılış ekranı üretilemedi; ikon üretildi.');
      }
    }

    stdout.writeln('\n✅ İkon hazır. Değişikliği görmek için uygulamayı '
        'yeniden kurun (flutter run).');
    return 0;
  }

  bool _run(String dir, List<String> args, String label) {
    stdout.writeln('\n▶ $label  (dart ${args.join(' ')})');
    final result = Process.runSync('dart', args, workingDirectory: dir);
    stdout.write(result.stdout);
    if (result.exitCode != 0) stderr.write(result.stderr);
    return result.exitCode == 0;
  }

  void _warnIfNotSquare1024(String imagePath) {
    if (!Platform.isMacOS) return;
    try {
      final r = Process.runSync(
          'sips', ['-g', 'pixelWidth', '-g', 'pixelHeight', imagePath]);
      final out = r.stdout.toString();
      final w = RegExp(r'pixelWidth: (\d+)').firstMatch(out)?.group(1);
      final h = RegExp(r'pixelHeight: (\d+)').firstMatch(out)?.group(1);
      if (w != null && h != null && !(w == '1024' && h == '1024')) {
        stdout.writeln('⚠️  Görsel ${w}x$h. Önerilen 1024x1024, saydamsız '
            '(App Store saydam ikonu reddeder).');
      }
    } catch (_) {
      // sips yoksa sessizce geç.
    }
  }

  int _fail(String message) {
    stderr.writeln('❌ $message');
    return 64;
  }
}
