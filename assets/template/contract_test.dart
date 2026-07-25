// Sözleşme testi — sunucunun beklenen davranışı verdiğini doğrular.
//
// Çalışan bir backend'e bakar; adresi --dart-define ile geçilir:
//
//   cd backend && docker compose up -d
//   cd ../app && flutter test test/api_contract_test.dart \
//     --dart-define=CONTRACT_API_URL=http://127.0.0.1:8000
//
// CONTRACT_API_URL verilmezse test atlanır (normal `flutter test`'i bozmaz).

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _base = String.fromEnvironment('CONTRACT_API_URL');

void main() {
  final skip = _base.isEmpty ? 'CONTRACT_API_URL verilmedi' : false;

  test('GET /health → {"status":"ok"}', () async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse('$_base/health'));
      final res = await req.close();
      expect(res.statusCode, 200);
      final body = await res.transform(utf8.decoder).join();
      expect(jsonDecode(body)['status'], 'ok');
    } finally {
      client.close();
    }
  }, skip: skip);

  test('push → pull turu kaydı geri getirir', () async {
    final client = HttpClient();
    try {
      final id = 'test-${DateTime.now().microsecondsSinceEpoch}';
      final item = {
        'id': id,
        'title': 'sözleşme',
        'body': '',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        'deleted': false,
      };

      final push = await client.postUrl(Uri.parse('$_base/sync/push'));
      push.headers.contentType = ContentType.json;
      push.write(jsonEncode([item]));
      final pushRes = await push.close();
      expect(pushRes.statusCode, 200);

      final pull = await client.getUrl(Uri.parse('$_base/sync/pull'));
      final pullRes = await pull.close();
      final body = await pullRes.transform(utf8.decoder).join();
      final ids = (jsonDecode(body) as List).map((e) => e['id']).toList();
      expect(ids, contains(id));
    } finally {
      client.close();
    }
  }, skip: skip);
}
