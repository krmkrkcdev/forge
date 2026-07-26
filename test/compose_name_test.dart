import 'package:test/test.dart';

import 'package:forge/src/compose.dart';

/// Compose proje adının doğru okunması bir emniyet kapısıdır: ad yoksa
/// "Sunucuya kur" durur. Yanlış pozitif (ad yokken var sanmak) kurulumun
/// aynı sunucudaki başka bir yığını silmesine izin verir — gerçekten
/// yaşandı, bu yüzden davranış burada sabitlenir.
void main() {
  group('compose proje adı', () {
    test('üst düzey name okunur', () {
      expect(
        composeProjectName('name: jumptoup\nservices:\n  db:\n'),
        'jumptoup',
      );
    });

    test('tırnak ve satır sonu yorumu temizlenir', () {
      expect(composeProjectName('name: "vaktinde"  # proje adı\n'), 'vaktinde');
      expect(composeProjectName("name: 'astrotas'\n"), 'astrotas');
    });

    test('ad yoksa null döner', () {
      expect(composeProjectName('services:\n  api:\n    build: .\n'), isNull);
    });

    test('container_name proje adı sanılmaz', () {
      const yaml = '''
services:
  api:
    container_name: jumptoup-api
''';
      expect(composeProjectName(yaml), isNull);
    });

    test('girintili name (volume/ağ adı) proje adı sanılmaz', () {
      const yaml = '''
services:
  api:
    build: .
networks:
  proxy:
    external: true
    name: proxy-network
volumes:
  pgdata:
    name: backend_pgdata
''';
      expect(composeProjectName(yaml), isNull);
    });

    test('yorum satırındaki name sayılmaz', () {
      const yaml = '''
# name: eski-proje
services:
  api:
    build: .
''';
      expect(composeProjectName(yaml), isNull);
    });

    test('boş name yok sayılır', () {
      expect(composeProjectName('name:\nservices:\n'), isNull);
    });
  });
}
