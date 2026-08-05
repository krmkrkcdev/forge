import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Makineye bir kez girilen, tüm projelerde aynı olan değerler.
///
/// `~/.forge/account.json` panel tarafından yazılır. Aynı dosyayı komut
/// satırı da okur: Apple takım kimliği gibi bilgileri her yeni projede
/// yeniden girmek ya da sonradan hata olarak görmek gereksiz.
///
/// Dosya kullanıcının gerçek verisidir; okunamıyorsa sessizce boş dönülür
/// ve proje üretimi bundan etkilenmez.
class ForgeAccount {
  const ForgeAccount(this.values);

  final Map<String, String> values;

  static String get directory {
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.current.path;
    return p.join(home, '.forge');
  }

  static String get file => p.join(directory, 'account.json');

  static ForgeAccount read() {
    final f = File(file);
    if (!f.existsSync()) return const ForgeAccount({});
    try {
      final decoded = jsonDecode(f.readAsStringSync());
      if (decoded is! Map) return const ForgeAccount({});
      return ForgeAccount({
        for (final e in decoded.entries)
          e.key.toString(): e.value?.toString() ?? '',
      });
    } on FormatException {
      return const ForgeAccount({});
    } on FileSystemException {
      return const ForgeAccount({});
    }
  }

  String? operator [](String key) {
    final value = values[key];
    return (value == null || value.isEmpty) ? null : value;
  }

  /// Apple Developer takım kimliği. İmzalama bunsuz kurulamaz.
  String? get appleTeamId => this['APPLE_TEAM_ID'];
}
