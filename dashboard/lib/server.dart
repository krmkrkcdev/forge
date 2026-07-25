import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;

import 'handlers.dart';

/// Sunucuyu yalnızca localhost'ta başlatır.
///
/// Bağlama adresi bilinçli olarak [InternetAddress.loopbackIPv4]: panel kabuk
/// komutu çalıştırdığı için dış ağdan erişilebilir olması güvenlik açığıdır.
Future<HttpServer> startServer(Handlers handlers, {int port = 4577}) {
  final handler =
      const Pipeline().addMiddleware(_logRequests()).addHandler(handlers.router);
  return io.serve(handler, InternetAddress.loopbackIPv4, port);
}

/// Kısa istek günlüğü — panelin ne yaptığı terminalden izlenebilsin.
Middleware _logRequests() => (inner) => (request) async {
      final response = await inner(request);
      // Statik dosya isteklerini gürültü yapmasın diye atlıyoruz.
      if (request.url.path.startsWith('api/')) {
        stdout.writeln('  ${request.method} /${request.url}  → '
            '${response.statusCode}');
      }
      return response;
    };
