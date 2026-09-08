import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:{{PROJECT_NAME}}/screens/splash_screen.dart';
import 'package:{{PROJECT_NAME}}/services/ad_service.dart';
import 'package:{{PROJECT_NAME}}/theme/app_theme.dart';

/// İskeletle gelen duman testi.
///
/// Bu dosya yalnızca örnek değil, çalışma şartıdır: `flutter test`, hiç test
/// dosyası bulamazsa 1 koduyla çıkar ve hem AGENTS.md'deki doğrulama adımı
/// hem de deploy.sh'ın kalite kontrolü daha ilk günden başarısız olur.
/// Kendi testlerinizi yazınca bu dosyayı silebilirsiniz — yeter ki geriye
/// en az bir test dosyası kalsın.
void main() {
  test('geliştirme derlemesi test reklam kimliklerini kullanır', () {
    // Gerçek kimlikler yalnızca deploy.sh'ın verdiği --dart-define ile
    // girer. Bu test, birinin kimlikleri koda gömmesini yakalar: gerçek
    // kimlikle geliştirme yapıp kendi reklamına tıklamak AdMob hesabının
    // kapatılmasına yol açar.
    expect(AdService.usingTestIds, isTrue);
  });

  test('tema iki modda da kurulur', () {
    expect(AppTheme.light().useMaterial3, isTrue);
    expect(AppTheme.dark().useMaterial3, isTrue);
  });

  testWidgets('açılış ekranı markayı ve logoyu gösterir', (tester) async {
    // Logo dosyası pubspec'te beyan edilmemişse Image.asset sessizce boş
    // döner (errorBuilder) ve açılış kapkara kalır; bu test onu yakalar.
    await tester.pumpWidget(const MaterialApp(home: SplashScreen()));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('PikeLabs'), findsOneWidget);
    final image = tester.widget<Image>(find.byType(Image));
    final asset = image.image as AssetImage;
    expect(asset.assetName, 'assets/splash/pikelabs.png');
    await expectLater(
      rootBundle.load(asset.assetName),
      completes,
      reason: 'assets/splash/ pubspec.yaml içinde beyan edilmeli',
    );

    // Süre dolmadan söküyoruz: HomeScreen'e geçiş reklam SDK'sını
    // başlatır, o da testte platform kanalı ister.
    await tester.pumpWidget(const SizedBox());
  });
}
