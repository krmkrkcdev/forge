// Şablon dosyalarını Dart koduna gömer.
//
// forge küresel olarak kurulduğunda (`dart pub global activate`) çalıştırılan
// şey bir anlık görüntüdür; yanındaki assets/ dizinini güvenilir biçimde
// bulmanın taşınabilir bir yolu yok. Bu yüzden şablonlar derlenmiş koda
// gömülür.
//
// Kaynak yine assets/template/ altındaki GERÇEK dosyalardır: orada
// düzenlenir, biçimlendirici ve shellcheck orada çalışır. Bu araç yalnızca
// onları taşınabilir hâle getirir.
//
// Şablonu değiştirdikten sonra:
//
//   dart run tool/bundle_assets.dart
//
// Unutursanız `dart test` yakalar (test/bundle_test.dart).

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

const _assetRoot = 'assets/template';
const _output = 'lib/src/templates/bundle.dart';

void main(List<String> args) {
  final check = args.contains('--check');
  final generated = generateBundle();
  final file = File(_output);

  if (check) {
    final current = file.existsSync() ? file.readAsStringSync() : '';
    if (current != generated) {
      stderr.writeln('❌ $_output güncel değil. Çalıştırın: '
          'dart run tool/bundle_assets.dart');
      exit(1);
    }
    stdout.writeln('✅ $_output güncel.');
    return;
  }

  file.parent.createSync(recursive: true);
  file.writeAsStringSync(generated);
  stdout.writeln('✅ ${templateFilePaths().length} şablon dosyası gömüldü → '
      '$_output');
}

/// Gömülecek dosyaların göreli yolları, sıralı.
///
/// Sıra sabit olmalı: aksi hâlde dosya sisteminin sıralaması değiştiğinde
/// üretilen dosya sebepsiz yere değişir ve fark (diff) gürültüsü olur.
List<String> templateFilePaths() {
  final root = Directory(_assetRoot);
  final paths = root
      .listSync(recursive: true)
      .whereType<File>()
      .map((f) => p.relative(f.path, from: _assetRoot))
      .where((path) => !path.endsWith('.DS_Store'))
      .toList()
    ..sort();
  return paths;
}

String generateBundle() {
  final buffer = StringBuffer()
    ..writeln('// ÜRETİLMİŞ DOSYA — elle düzenlemeyin.')
    ..writeln('//')
    ..writeln('// Kaynak: $_assetRoot/')
    ..writeln('// Yeniden üretmek için: dart run tool/bundle_assets.dart')
    ..writeln()
    ..writeln("import 'dart:convert';")
    ..writeln()
    ..writeln('/// Şablon dosyaları: göreli yol → base64 içerik.')
    ..writeln('///')
    ..writeln('/// base64 tercih edildi çünkü şablonlar hem Dart hem shell hem')
    ..writeln('/// XML kaçış dizileri içeriyor; kaçırılmış tek bir karakter')
    ..writeln('/// üretilen projeyi sessizce bozardı.')
    ..writeln('const Map<String, String> _encoded = {');

  for (final path in templateFilePaths()) {
    final bytes = File(p.join(_assetRoot, path)).readAsBytesSync();
    final encoded = base64.encode(bytes);
    buffer.writeln("  '$path':");
    if (encoded.isEmpty) {
      // Boş dosya (ör. __init__.py): geçerli Dart için yine bir değer gerekir.
      buffer.writeln("      ''");
    } else {
      // Uzun satırlar diff'i okunmaz kılar; sabit genişlikte bölüyoruz.
      for (final chunk in _chunks(encoded, 70)) {
        buffer.writeln("      '$chunk'");
      }
    }
    buffer.writeln('      ,');
  }

  buffer
    ..writeln('};')
    ..writeln()
    ..writeln('/// Şablondaki dosya yolları.')
    ..writeln('Iterable<String> get templatePaths => _encoded.keys;')
    ..writeln()
    ..writeln('/// Şablon dosyasının içeriği; yoksa `null`.')
    ..writeln('String? templateFile(String path) {')
    ..writeln('  final encoded = _encoded[path];')
    ..writeln('  if (encoded == null) return null;')
    ..writeln('  return utf8.decode(base64.decode(encoded));')
    ..writeln('}');

  return buffer.toString();
}

Iterable<String> _chunks(String value, int size) sync* {
  for (var i = 0; i < value.length; i += size) {
    yield value.substring(i, i + size > value.length ? value.length : i + size);
  }
}
