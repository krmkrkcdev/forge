import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'screens/home_screen.dart';
import 'services/ad_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Uygulama yalnızca dikey yönde tasarlandı. Yatay düzen ekleyecekseniz
  // ios/Runner/Info.plist içindeki UIRequiresFullScreen kaydını da gözden
  // geçirin — iPad'de çoklu görev açıksa dört yönün de beyan edilmesi
  // gerekir, yoksa App Store Connect yüklemeyi reddeder.
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  await initializeDateFormatting('tr_TR');

  // Reklam SDK'sı açılışı bloklamamalı: ağ bekler ve hata verse bile
  // uygulama tam olarak çalışmaya devam eder. Reklam hiçbir zaman
  // uygulamanın çalışma şartı değildir.
  unawaited(AdService.instance.init());

  runApp(const {{APP_CLASS}}());
}

class {{APP_CLASS}} extends StatelessWidget {
  const {{APP_CLASS}}({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '{{APP_NAME}}',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      locale: const Locale('tr', 'TR'),
      supportedLocales: const [Locale('tr', 'TR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const HomeScreen(),
    );
  }
}
