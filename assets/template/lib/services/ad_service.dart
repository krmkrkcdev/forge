import 'dart:async';
import 'dart:io';

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
// widgets.dart, foundation.dart'ı da dışa aktarır (debugPrint, ValueNotifier).
// Buradaki fazlası WidgetsBinding: ATT diyaloğu uygulama ETKİN duruma
// geçmeden gösterilemez, o yüzden yaşam döngüsüne bakmamız gerekiyor.
import 'package:flutter/widgets.dart';
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

  // ------------------------------------------------- izleme izni (ATT)

  /// Apple'ın izleme izni diyaloğunu gösterir (yalnızca iOS).
  ///
  /// **UMP onay formu bunun yerine geçmez.** Google'ın formu Google'ın
  /// yayıncı politikası (GDPR/DMA) içindir; Apple ise reklam kimliğine
  /// (IDFA) erişmek için KENDİ diyaloğunu şart koşar. Yalnızca UMP formunu
  /// gösteren uygulama, Apple'ın gözünde "izleme izni isteyen özel ekran"
  /// gösteriyordur ve **5.1.2(i)** ile reddedilir. Bu kural gerçek bir
  /// redden doğdu; ayrıntısı docs/REKLAM.md içinde.
  ///
  /// İzin verilmezse hiçbir şey bozulmaz: reklamlar kişiselleştirilmemiş
  /// olarak sunulmaya devam eder. Reklam hiçbir zaman uygulamanın çalışma
  /// şartı değildir.
  Future<void> _requestTrackingAuthorization() async {
    if (!Platform.isIOS) return;

    // Karar kullanıcı ömrü boyunca BİR KEZ verilir; verilmişse iOS diyaloğu
    // bir daha göstermez, eski cevabı sessizce döndürür. Boşuna beklememek
    // için önce mevcut duruma bakıyoruz.
    final current = await AppTrackingTransparency.trackingAuthorizationStatus;
    if (current != TrackingStatus.notDetermined) return;

    await _waitUntilResumed();

    final status = await AppTrackingTransparency.requestTrackingAuthorization();
    debugPrint('ATT izni: $status');
  }

  /// Uygulama ETKİN (resumed) duruma geçene kadar bekler.
  ///
  /// iOS izin diyaloğunu yalnızca uygulama ön planda ve etkinken gösterir.
  /// Açılışta, ilk kare çizilmeden istenen izin **diyalog hiç çıkmadan**
  /// `notDetermined` ile geri döner ve bir daha sorulamaz. Hata mesajı
  /// yoktur; yalnızca izin alınmamış olur — ve inceleme "izin istenmiyor"
  /// diyerek reddeder. Bu yüzden bekleme kaldırılamaz.
  ///
  /// Süre sınırı var: uygulama arka planda açıldıysa (ör. bildirimle)
  /// sonsuza kadar beklemek yerine vazgeçilir, izin bir sonraki açılışta
  /// istenir.
  Future<void> _waitUntilResumed() async {
    final binding = WidgetsBinding.instance;
    await binding.endOfFrame;

    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (binding.lifecycleState != AppLifecycleState.resumed &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
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

  /// Sıra üç adımdır ve DEĞİŞTİRİLEMEZ:
  ///
  /// 1. UMP onayı — AB/İngiltere için zorunlu; AdMob konsolunda ATT
  ///    açıklayıcı mesajı tanımlıysa Google onu da burada gösterir.
  /// 2. Apple'ın izleme izni (ATT) — açıklayıcı ekrandan SONRA gelmelidir,
  ///    yoksa açıklama anlamsızlaşır; Apple'ın istediği de bu sıradır.
  /// 3. SDK başlatma — izin durumu belli olmadan ilk reklam isteği giderse
  ///    o istek IDFA'sız gider ve gelir kalıcı olarak düşer.
  Future<void> _init() async {
    final canRequestAds = await _gatherConsent();

    // Onay sonucundan BAĞIMSIZ olarak istenir: diyalog kullanıcı ömrü
    // boyunca bir kez çıkar ve App Store incelemesinin görmesi gereken
    // ekran budur. Onay reddedildiğinde erken dönüp bunu atlamak, incelemede
    // "izin hiç istenmiyor" olarak görünür.
    await _requestTrackingAuthorization();

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
