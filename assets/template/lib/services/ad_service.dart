import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Reklam altyapısı — bütün uygulamalarda AYNI dosya.
///
/// Bu dosya uygulamaya özel hiçbir şeye bağlı değildir (durum yönetimi,
/// ayarlar deposu, ekran adları). Yeni bir uygulamaya olduğu gibi kopyalanır;
/// uygulamaya özel olan tek şey `--dart-define` ile verilen kimliklerdir.
///
/// Kurallar ve gerekçeleri için: docs/REKLAM.md
class AdService {
  AdService._();

  static final AdService instance = AdService._();

  // ------------------------------------------------------------- kimlikler

  /// Google'ın herkese açık test kimlikleri.
  ///
  /// Varsayılan bilinçli olarak testtir: gerçek kimliklerle geliştirme yapıp
  /// kendi reklamınıza tıklamak AdMob hesabının KAPATILMASINA yol açar ve bu
  /// karar temyiz edilemez. Gerçek kimlikler yalnızca yayın derlemesinde,
  /// deploy.sh üzerinden `--dart-define` ile girer.
  static const testBannerId = 'ca-app-pub-3940256099942544/2934735716';
  static const testInterstitialId = 'ca-app-pub-3940256099942544/4411468910';

  /// Google'ın test UYGULAMA kimliğinin ortak parçası.
  ///
  /// Info.plist ve AndroidManifest.xml içindeki değer bunu içeriyorsa
  /// uygulama yayında test reklamı gösteriyor demektir — yani geliri sıfırdır.
  /// `forge doctor` bunu denetler.
  static const testApplicationIdPublisher = 'ca-app-pub-3940256099942544';

  static const _bannerIos =
      String.fromEnvironment('ADMOB_BANNER_IOS', defaultValue: testBannerId);
  static const _bannerAndroid =
      String.fromEnvironment('ADMOB_BANNER_ANDROID', defaultValue: testBannerId);
  static const _interstitialIos = String.fromEnvironment(
    'ADMOB_INTERSTITIAL_IOS',
    defaultValue: testInterstitialId,
  );
  static const _interstitialAndroid = String.fromEnvironment(
    'ADMOB_INTERSTITIAL_ANDROID',
    defaultValue: testInterstitialId,
  );

  static String get bannerUnitId => Platform.isIOS ? _bannerIos : _bannerAndroid;
  static String get interstitialUnitId =>
      Platform.isIOS ? _interstitialIos : _interstitialAndroid;

  /// Bu derleme test reklamı gösteriyor mu?
  ///
  /// İki platforma da bakar: yalnızca birine bakmak, tek platformun kimliği
  /// unutulduğunda sorunu görünmez kılar — gerçekten başımıza gelen bir hata.
  static bool get usingTestIds =>
      _bannerIos == testBannerId ||
      _bannerAndroid == testBannerId ||
      _interstitialIos == testInterstitialId ||
      _interstitialAndroid == testInterstitialId;

  // ------------------------------------------------------------- premium

  /// Reklamların kapalı olup olmadığı.
  ///
  /// Uygulama premium durumunu değiştirdiğinde [setPremium] çağırır; banner
  /// bunu dinlediği için satın alma biter bitmez reklam kaybolur, uygulamayı
  /// yeniden başlatmak gerekmez.
  final ValueNotifier<bool> isPremium = ValueNotifier<bool>(false);

  void setPremium(bool value) {
    if (isPremium.value == value) return;
    isPremium.value = value;
    if (value) {
      _interstitial?.dispose();
      _interstitial = null;
    }
  }

  // ------------------------------------------------------------- onay (UMP)

  /// Avrupa'daki kullanıcıya gizlilik seçenekleri düğmesi gösterilmeli mi?
  ///
  /// Gerekli olduğu hâlde gösterilmemesi Google'ın yayıncı politikasının
  /// ihlalidir; ayarlar ekranı bunu dinleyip satırı gizler/gösterir.
  final ValueNotifier<bool> privacyOptionsRequired = ValueNotifier<bool>(false);

  /// Kullanıcıya gizlilik seçenekleri formunu gösterir.
  ///
  /// Ayarlar ekranındaki "Reklam gizlilik seçenekleri" satırına bağlanır.
  Future<void> showPrivacyOptions() async {
    await ConsentForm.showPrivacyOptionsForm((error) {
      if (error != null) {
        debugPrint('Gizlilik seçenekleri formu açılamadı: ${error.message}');
      }
      _refreshPrivacyOptionsRequirement();
    });
  }

  Future<void> _refreshPrivacyOptionsRequirement() async {
    final status =
        await ConsentInformation.instance.getPrivacyOptionsRequirementStatus();
    privacyOptionsRequired.value =
        status == PrivacyOptionsRequirementStatus.required;
  }

  /// Onay bilgisini günceller ve gerekiyorsa onay formunu gösterir.
  ///
  /// AB/İngiltere kullanıcılarına onay formu göstermek zorunludur; formu
  /// atlayan uygulamaya bu bölgelerde reklam sunulmaz ve hesap politika
  /// ihlaline düşer. Form yalnızca gerekli olduğunda çıkar, bu yüzden
  /// koşulsuz çağrılır.
  ///
  /// Onay alınamazsa reklamsız devam edilir — uygulamanın kendisi çalışmayı
  /// sürdürür. Reklam hiçbir zaman uygulamanın çalışma şartı değildir.
  Future<bool> _gatherConsent() async {
    final params = ConsentRequestParameters();
    final completer = Completer<void>();

    ConsentInformation.instance.requestConsentInfoUpdate(
      params,
      () => completer.complete(),
      (error) {
        debugPrint('Onay bilgisi alınamadı: ${error.message}');
        completer.complete();
      },
    );
    await completer.future;

    await ConsentForm.loadAndShowConsentFormIfRequired((error) {
      if (error != null) {
        debugPrint('Onay formu gösterilemedi: ${error.message}');
      }
    });

    await _refreshPrivacyOptionsRequirement();
    return ConsentInformation.instance.canRequestAds();
  }

  // ------------------------------------------------------------- yaşam döngüsü

  bool _initialized = false;
  Future<void>? _initializing;

  /// Reklam SDK'sını hazırlar. Birden çok kez çağrılabilir.
  ///
  /// Aynı anda gelen çağrılar tek bir hazırlığı bekler: banner ile ana ekran
  /// başlatmayı çoğu zaman aynı karede tetikler.
  Future<void> init() {
    if (_initialized) return Future.value();
    return _initializing ??= _init();
  }

  Future<void> _init() async {
    final canRequestAds = await _gatherConsent();
    if (!canRequestAds) {
      // Onay yok: SDK'yı başlatmanın anlamı yok, reklam sunulmayacak.
      _initializing = null;
      return;
    }
    await MobileAds.instance.initialize();
    _initialized = true;
    _preloadInterstitial();
  }

  /// Hazır mı? Banner bunu bilmeli: hazır değilken yer ayırmamalı.
  bool get isReady => _initialized;

  // ------------------------------------------------- tam ekran reklam kuralı

  /// Tam ekran reklam en erken bu kadar "değerli eylem"den sonra çıkar.
  static const _showEveryNActions = 4;

  /// İki tam ekran reklam arasındaki en kısa süre.
  static const _minGapBetweenAds = Duration(minutes: 5);

  /// Uygulama açıldıktan sonra tam ekran reklam için beklenen en kısa süre.
  ///
  /// Açılıştan hemen sonra gelen reklam, kullanıcının uygulamayı bir işi
  /// olduğu için açtığı anda önüne çıkar; kaldırma oranını en çok artıran
  /// yerleşim budur.
  static const _minTimeSinceLaunch = Duration(seconds: 45);

  final DateTime _launchedAt = DateTime.now();
  int _actionsSinceAd = 0;
  DateTime? _lastInterstitialAt;
  InterstitialAd? _interstitial;

  void _preloadInterstitial() {
    if (isPremium.value || _interstitial != null) return;
    InterstitialAd.load(
      adUnitId: interstitialUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) => _interstitial = ad,
        onAdFailedToLoad: (error) {
          // Reklam yüklenemezse uygulama normal çalışmaya devam eder.
          debugPrint('Tam ekran reklam yüklenemedi: ${error.message}');
          _interstitial = null;
        },
      ),
    );
  }

  /// Kullanıcı "değerli bir eylemi" TAMAMLADIĞINDA çağrılır.
  ///
  /// Değerli eylem = kullanıcının işini bitirdiği an (kaydı tamamlama,
  /// bölümü bitirme). Kayıt oluşturma ve düzenleme akışlarının ORTASINDA
  /// asla çağrılmaz: kullanıcıyı işinden koparan reklam hem kaldırılmaya
  /// hem de kötü puana yol açar.
  ///
  /// Koşullar tutmazsa sessizce hiçbir şey yapmaz.
  Future<void> onValuableAction() async {
    if (isPremium.value) return;
    await init();
    if (!_initialized) return;

    _actionsSinceAd++;
    if (_actionsSinceAd < _showEveryNActions) return;
    if (DateTime.now().difference(_launchedAt) < _minTimeSinceLaunch) return;

    final last = _lastInterstitialAt;
    if (last != null && DateTime.now().difference(last) < _minGapBetweenAds) {
      return;
    }

    final ad = _interstitial;
    if (ad == null) {
      _preloadInterstitial();
      return;
    }

    _actionsSinceAd = 0;
    _lastInterstitialAt = DateTime.now();
    _interstitial = null;

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _preloadInterstitial();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _preloadInterstitial();
      },
    );
    await ad.show();
  }

  void dispose() {
    _interstitial?.dispose();
    _interstitial = null;
  }
}
