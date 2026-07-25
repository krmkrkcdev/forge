import 'dart:io';

import 'package:args/args.dart';

import 'lib/handlers.dart';
import 'lib/server.dart';

/// forge kontrol paneli — yerel sunucu.
///
/// forge zaten bir Dart kütüphanesi olduğu için panel `runChecks()` gibi
/// fonksiyonları doğrudan çağırır; yayın hattını (deploy.sh) ise alt süreç
/// olarak başlatıp çıktısını canlı akıtır.
///
/// GÜVENLİK: Sunucu kabuk komutu çalıştırabildiği için YALNIZCA localhost'a
/// bağlanır. Ağa açılırsa makinenizi başkasının eline verirsiniz. Bu yüzden
/// dinleme adresi bilinçli olarak sabit ve değiştirilemez.
Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('port', abbr: 'p', defaultsTo: '4577', help: 'Dinlenecek port.')
    ..addOption('base',
        help: 'Uygulama projelerinin arandığı kök dizin. '
            'Varsayılan: forge deposunun bulunduğu üst dizin.')
    ..addFlag('open',
        defaultsTo: true, help: 'Tarayıcıyı otomatik açar (macOS).')
    ..addFlag('help', abbr: 'h', negatable: false);

  final args = parser.parse(arguments);
  if (args['help'] as bool) {
    stdout.writeln('forge kontrol paneli\n\n${parser.usage}');
    return;
  }

  final forgeRoot = resolveForgeRoot();
  final base = (args['base'] as String?) ?? Directory(forgeRoot).parent.path;
  final port = int.tryParse(args['port'] as String) ?? 4577;

  final handlers = Handlers(forgeRoot: forgeRoot, projectsBase: base);
  final server = await startServer(handlers, port: port);

  final url = 'http://localhost:${server.port}';
  stdout.writeln('🔨 forge paneli çalışıyor:  $url');
  stdout.writeln('   Projeler taranıyor:      $base');
  stdout.writeln('   Durdurmak için:          Ctrl+C\n');

  if ((args['open'] as bool) && Platform.isMacOS) {
    await Process.run('open', [url]);
  }
}
