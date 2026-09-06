import 'dart:io';

import 'package:args/command_runner.dart';

import '../project.dart';

/// Projeyi derleme turunu harcamadan statik olarak denetler.
///
/// `forge doctor` mağaza hazırlığına bakar — dosyalar, kimlikler, beyanlar.
/// Kodun kendisine bakmaz. Derleme hatasını ya da analiz uyarısını yayın
/// akışının içinde öğrenmek pahalıdır: `deploy.sh` önce temizlik, sonra
/// `flutter build` yapar; hata dakikalar sonra, imzalama adımının hemen
/// öncesinde patlar. Bu komut aynı bilgiyi saniyeler içinde verir.
class AnalyzeCommand extends Command<int> {
  AnalyzeCommand() {
    argParser
      ..addOption(
        'path',
        abbr: 'p',
        help: 'Denetlenecek Flutter projesinin yolu.',
        defaultsTo: '.',
      )
      ..addFlag(
        'pub-get',
        help: 'Analizden önce bağımlılıkları çözer.',
        defaultsTo: true,
      );
  }

  @override
  String get name => 'analyze';

  @override
  String get description =>
      'Bağımlılıkları çözer ve flutter analyze çalıştırır.';

  @override
  Future<int> run() async {
    final searchPath = argResults!['path'] as String;
    final project = FlutterProject.locate(searchPath);
    if (project == null) {
      stderr.writeln('❌ Flutter projesi bulunamadı: '
          '${Directory(searchPath).absolute.path}');
      stderr.writeln('   Bu dizinde ve üst dizinlerinde pubspec.yaml yok.');
      return 2;
    }

    stdout.writeln('🔎 Analiz edilen proje: ${project.appName ?? project.root}');
    stdout.writeln('   ${project.root}\n');

    // Bağımlılıklar çözülmeden analiz, her import için "target of URI doesn't
    // exist" üretir — yüzlerce sahte hata. Yeni paket eklendikten sonra en sık
    // karşılaşılan durum tam olarak budur, o yüzden varsayılan açık.
    if (argResults!['pub-get'] as bool) {
      final resolved = await _spawn('flutter', ['pub', 'get'], project.root);
      if (resolved != 0) {
        stderr.writeln('\n❌ Bağımlılıklar çözülemedi; analiz çalıştırılmadı.');
        return resolved;
      }
      stdout.writeln('');
    }

    final code = await _spawn('flutter', ['analyze'], project.root);
    stdout.writeln('');
    if (code == 0) {
      stdout.writeln('✅ Analiz temiz.');
    } else {
      stdout.writeln('⛔ Analiz bulgu bildirdi. Yayın akışına girmeden '
          'düzeltin: build turu dakikalar sürer, bu bilgi saniyeler.');
    }
    return code;
  }

  /// Alt süreci çalıştırır ve çıktısını olduğu gibi aktarır.
  ///
  /// Çıktı biriktirilip sonda basılmaz: `flutter pub get` ağ bekler,
  /// `flutter analyze` büyük projede uzun sürer; ilerlemeyi görmek gerekir.
  Future<int> _spawn(String executable, List<String> arguments, String cwd) async {
    try {
      final process = await Process.start(
        executable,
        arguments,
        workingDirectory: cwd,
        mode: ProcessStartMode.inheritStdio,
      );
      return process.exitCode;
    } on ProcessException catch (e) {
      stderr.writeln('❌ $executable çalıştırılamadı: ${e.message}');
      stderr.writeln('   Flutter SDK kurulu ve PATH\'te mi?');
      return 127;
    }
  }
}
