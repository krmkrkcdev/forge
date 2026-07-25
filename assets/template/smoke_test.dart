import 'package:flutter_test/flutter_test.dart';
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
}
