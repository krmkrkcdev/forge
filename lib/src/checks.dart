import 'dart:io' as io;

import 'finding.dart';
import 'project.dart';

/// Mağaza hazırlık denetimleri.
///
/// Buradaki her kural, gerçek bir yayında karşılaşılmış bir engelden
/// türetilmiştir. Yeni bir tuzağa düştüğünüzde çözümü buraya kural olarak
/// ekleyin — bir daha aynı yerde takılmazsınız.
typedef Check = Finding? Function(FlutterProject project);

const List<Check> allChecks = [
  _versionFormat,
  _androidReleaseSigning,
  _androidInternetPermission,
  _iosExportCompliance,
  _iosPrivacyManifest,
  _iosPrivacyManifestRegistered,
  _iosPermissionStrings,
  _iosSigningTeam,
  _iosIpadOrientations,
  _secretsNotIgnored,
  _bundleIdMatch,
  _defaultBundleId,
  _launcherIcon,
  _appDescription,
  _cleartextTrafficInRelease,
];

List<Finding> runChecks(FlutterProject project) {
  final findings = <Finding>[];
  for (final check in allChecks) {
    final finding = check(project);
    if (finding != null) findings.add(finding);
  }
  // Önce engeller, sonra uyarılar.
  findings.sort((a, b) => a.severity.index.compareTo(b.severity.index));
  return findings;
}

// --------------------------------------------------------------- sürümleme

Finding? _versionFormat(FlutterProject p) {
  final version = p.versionValue;
  if (version == null) {
    return const Finding(
      id: 'version-missing',
      severity: Severity.blocker,
      platform: Platform.both,
      title: 'pubspec.yaml içinde version satırı yok',
      why: 'Build numarası hem iOS (CURRENT_PROJECT_VERSION) hem Android '
          '(versionCode) için buradan gelir. Yayın akışı bu satır olmadan '
          'başlayamaz.',
      fix: 'pubspec.yaml içine ekleyin:  version: 1.0.0+1',
      autoFixable: true,
    );
  }
  if (!version.contains('+')) {
    return Finding(
      id: 'version-no-build-number',
      severity: Severity.blocker,
      platform: Platform.both,
      title: 'Sürümde build numarası yok: "$version"',
      why: 'Mağazalar aynı build numarasını iki kez kabul etmez. Build '
          'numarası olmadan yayın betiği hiç başlamaz.',
      fix: 'Biçimi düzeltin:  version: $version+1',
      autoFixable: true,
    );
  }
  return null;
}

// ----------------------------------------------------------------- Android

Finding? _androidReleaseSigning(FlutterProject p) {
  if (!p.hasAndroid) return null;

  final usesDebugSigning = p.contains(
        'android/app/build.gradle.kts',
        'signingConfigs.getByName("debug")',
      ) ||
      p.contains('android/app/build.gradle', "signingConfigs.debug");

  final hasKeyProperties = p.exists('android/key.properties');
  final readsKeyProperties = p.contains('android/app/build.gradle.kts', 'key.properties') ||
      p.contains('android/app/build.gradle', 'key.properties');

  if (!readsKeyProperties && usesDebugSigning) {
    return const Finding(
      id: 'android-debug-signing',
      severity: Severity.blocker,
      platform: Platform.android,
      title: 'Sürüm derlemesi debug anahtarıyla imzalanıyor',
      why: 'Play Console debug anahtarıyla imzalanmış paketi reddeder. '
          'Bunu ancak tam bir build ve yükleme turunu harcadıktan sonra '
          'öğrenirsiniz.',
      fix: 'android/app/build.gradle.kts içinde imzalamayı '
          'android/key.properties dosyasından okuyun. Anahtar deposunu '
          'keytool ile bir kez üretip GÜVENLE YEDEKLEYİN — kaybederseniz '
          'uygulamanın güncellemesini bir daha yükleyemezsiniz.',
    );
  }

  if (readsKeyProperties && !hasKeyProperties) {
    return const Finding(
      id: 'android-key-properties-missing',
      severity: Severity.warning,
      platform: Platform.android,
      title: 'android/key.properties bulunamadı',
      why: 'Yapılandırma hazır ama anahtar dosyası yok; sürüm derlemesi '
          'debug anahtarına düşer ve Play Store kabul etmez.',
      fix: 'android/key.properties.example dosyasını kopyalayıp doldurun.',
    );
  }
  return null;
}

Finding? _androidInternetPermission(FlutterProject p) {
  if (!p.hasAndroid) return null;
  final manifest = p.androidManifest;
  if (manifest == null) return null;

  // Ağ kullanan bir paket var mı?
  final pubspec = p.pubspec ?? '';
  final usesNetwork = ['http:', 'dio:', 'web_socket', 'grpc', 'firebase']
      .any(pubspec.contains);
  if (!usesNetwork) return null;

  if (!manifest.contains('android.permission.INTERNET')) {
    return const Finding(
      id: 'android-internet-permission',
      severity: Severity.blocker,
      platform: Platform.android,
      title: 'Ana manifestte INTERNET izni yok',
      why: 'Flutter bu izni yalnızca debug/profile derlemelerine kendiliğinden '
          'ekler. Ana manifestte yoksa ağ istekleri SADECE sürüm derlemesinde '
          'sessizce başarısız olur — bulunması en zor hata türlerinden biri.',
      fix: 'android/app/src/main/AndroidManifest.xml içine ekleyin:\n'
          '  <uses-permission android:name="android.permission.INTERNET"/>',
      autoFixable: true,
    );
  }
  return null;
}

Finding? _cleartextTrafficInRelease(FlutterProject p) {
  if (!p.hasAndroid) return null;
  final manifest = p.androidManifest;
  if (manifest == null) return null;

  if (manifest.contains('android:usesCleartextTraffic="true"')) {
    return const Finding(
      id: 'android-cleartext-release',
      severity: Severity.warning,
      platform: Platform.android,
      title: 'Ana manifest düz metin (HTTP) trafiğine izin veriyor',
      why: 'Sürüm derlemesinde tüm trafiğin şifresiz gitmesine izin verilir. '
          'Geliştirme için gerekiyorsa bu ayar debug manifestinde olmalı.',
      fix: 'usesCleartextTraffic satırını ana manifestten kaldırın; yerel '
          'sunucuya bağlanmak için android/app/src/debug/ altında '
          'network_security_config.xml kullanın.',
    );
  }
  return null;
}

// --------------------------------------------------------------------- iOS

Finding? _iosExportCompliance(FlutterProject p) {
  if (!p.hasIos) return null;
  final plist = p.iosInfoPlist;
  if (plist == null) return null;

  if (!plist.contains('ITSAppUsesNonExemptEncryption')) {
    return const Finding(
      id: 'ios-export-compliance',
      severity: Severity.warning,
      platform: Platform.ios,
      title: 'Info.plist içinde ITSAppUsesNonExemptEncryption yok',
      why: 'Bu anahtar olmadan App Store Connect HER yüklemede ihracat '
          'uyumluluğu sorusunu elle yanıtlamanızı bekler; otomatik yayın '
          'akışı orada durur.',
      fix: 'Uygulama standart HTTPS dışında şifreleme kullanmıyorsa '
          'ios/Runner/Info.plist içine ekleyin:\n'
          '  <key>ITSAppUsesNonExemptEncryption</key><false/>',
      autoFixable: true,
    );
  }
  return null;
}

Finding? _iosPrivacyManifest(FlutterProject p) {
  if (!p.hasIos) return null;
  if (p.exists('ios/Runner/PrivacyInfo.xcprivacy')) return null;

  return const Finding(
    id: 'ios-privacy-manifest',
    severity: Severity.warning,
    platform: Platform.ios,
    title: 'ios/Runner/PrivacyInfo.xcprivacy yok',
    why: 'Apple, gerekçe gerektiren API kullanan uygulamalarda gizlilik '
        'manifestini zorunlu tutuyor (UserDefaults, dosya zaman damgası, '
        'disk alanı bunlara dahil). Eksikse önce uyarı, sonra red gelir.',
    fix: 'PrivacyInfo.xcprivacy oluşturup topladığınız veri türlerini ve '
        'kullandığınız API gerekçelerini beyan edin. İçerik App Store '
        'Connect gizlilik anketiyle TUTARLI olmalıdır.',
  );
}

Finding? _iosPrivacyManifestRegistered(FlutterProject p) {
  if (!p.hasIos) return null;
  if (!p.exists('ios/Runner/PrivacyInfo.xcprivacy')) return null;

  if (!p.contains('ios/Runner.xcodeproj/project.pbxproj', 'PrivacyInfo.xcprivacy')) {
    return const Finding(
      id: 'ios-privacy-manifest-unregistered',
      severity: Severity.blocker,
      platform: Platform.ios,
      title: 'PrivacyInfo.xcprivacy var ama Xcode projesine kayıtlı değil',
      why: 'Dosya diskte duruyor ama uygulama paketine kopyalanmıyor. '
          'Apple onu göremez; dosyayı eklemiş olmanız hiçbir işe yaramaz. '
          'Sessizce başarısız olan bir durumdur.',
      fix: 'Xcode\'da dosyayı Runner hedefine sürükleyin ya da '
          'project.pbxproj içinde Copy Bundle Resources fazına ekleyin.',
    );
  }
  return null;
}

Finding? _iosPermissionStrings(FlutterProject p) {
  if (!p.hasIos) return null;
  final plist = p.iosInfoPlist;
  final pubspec = p.pubspec;
  if (plist == null || pubspec == null) return null;

  // Paket → gerekli Info.plist anahtarı
  const requirements = {
    'image_picker': ['NSCameraUsageDescription', 'NSPhotoLibraryUsageDescription'],
    'geolocator': ['NSLocationWhenInUseUsageDescription'],
    'record': ['NSMicrophoneUsageDescription'],
    'contacts_service': ['NSContactsUsageDescription'],
  };

  final missing = <String>[];
  requirements.forEach((package, keys) {
    if (!pubspec.contains('$package:')) return;
    for (final key in keys) {
      if (!plist.contains(key)) missing.add(key);
    }
  });

  if (missing.isEmpty) return null;
  return Finding(
    id: 'ios-permission-strings',
    severity: Severity.blocker,
    platform: Platform.ios,
    title: 'Info.plist içinde eksik izin açıklaması: ${missing.join(", ")}',
    why: 'iOS, açıklaması olmayan bir izni isteyen uygulamayı ÇALIŞMA ANINDA '
        'çökertir ve App Store incelemesi bunu reddeder.',
    fix: 'Her anahtar için kullanıcıya iznin neden gerektiğini anlatan bir '
        'metin ekleyin.',
  );
}

Finding? _iosSigningTeam(FlutterProject p) {
  if (!p.hasIos) return null;
  final pbxproj = p.read('ios/Runner.xcodeproj/project.pbxproj');
  if (pbxproj == null) return null;

  if (pbxproj.contains('DEVELOPMENT_TEAM')) return null;

  return const Finding(
    id: 'ios-no-development-team',
    severity: Severity.blocker,
    platform: Platform.ios,
    title: 'Xcode projesinde imzalama takımı (DEVELOPMENT_TEAM) tanımlı değil',
    why: 'Takım seçilmeden provisioning profile üretilemez, dolayısıyla arşiv '
        'de alınamaz. Xcode arayüzünde sarı bir uyarı olarak görünür ve '
        'kolayca gözden kaçar; yayın betiği ise anlaşılması güç bir imzalama '
        'hatasıyla durur.',
    fix: 'Xcode\'da Runner hedefi → Signing & Capabilities → Team seçin. '
        'Takım listesi boşsa Apple Developer Program üyeliğinizin etkin ve '
        'güncel sözleşmelerin kabul edilmiş olduğunu doğrulayın '
        '(developer.apple.com/terms).',
  );
}

Finding? _iosIpadOrientations(FlutterProject p) {
  if (!p.hasIos) return null;
  final plist = p.iosInfoPlist;
  if (plist == null) return null;

  // iPad hedeflenmiyorsa kural geçerli değil.
  final pbxproj = p.read('ios/Runner.xcodeproj/project.pbxproj') ?? '';
  if (!pbxproj.contains('TARGETED_DEVICE_FAMILY = "1,2"')) return null;

  // ~ipad dizisi dört yönü de içeriyorsa çoklu görev şartı zaten sağlanıyor.
  final ipadBlock = RegExp(
    r'UISupportedInterfaceOrientations~ipad</key>\s*<array>(.*?)</array>',
    dotAll: true,
  ).firstMatch(plist)?.group(1);
  if (ipadBlock == null) return null;

  final hasLandscape = ipadBlock.contains('LandscapeLeft') &&
      ipadBlock.contains('LandscapeRight');
  if (hasLandscape) return null;

  // Yatay yön beyan edilmemişse çoklu görev kapatılmış olmalı.
  if (plist.contains('UIRequiresFullScreen')) return null;

  return const Finding(
    id: 'ios-ipad-orientation-mismatch',
    severity: Severity.blocker,
    platform: Platform.ios,
    title: 'iPad yön beyanı eksik ve UIRequiresFullScreen yok',
    why: 'Uygulama iPad\'i hedefliyor ama iPad için yatay yönleri beyan '
        'etmiyor. iPad\'de çoklu görev (Split View) destekleyen uygulamalar '
        'dört yönü de beyan etmek zorundadır. App Store Connect yüklemeyi '
        '90474 hatasıyla REDDEDER — ve bunu ancak derleme, imzalama ve '
        'yükleme turunu tamamen harcadıktan sonra öğrenirsiniz.',
    fix: 'Uygulamanın yatay düzeni yoksa Info.plist içine ekleyin:\n'
        '  <key>UIRequiresFullScreen</key><true/>\n'
        'Yatay düzeni destekleyecekseniz onun yerine ~ipad dizisine '
        'LandscapeLeft ve LandscapeRight ekleyin. Üçüncü seçenek: iPad\'i '
        'hedeflemeyi bırakmak (TARGETED_DEVICE_FAMILY = "1").',
  );
}

// ------------------------------------------------------------------- ortak

/// Korunması gereken bir sır dosyası türü.
class SecretKind {
  const SecretKind(this.probe, this.label, this.pattern);

  /// Git'e sorulacak yol. Dosyanın var olması GEREKMEZ — `git check-ignore`
  /// saf yol eşleştirmesi yapar.
  final String probe;

  /// Kullanıcıya gösterilen ad.
  final String label;

  /// .gitignore'a yazılacak desen.
  final String pattern;
}

/// Anahtar dosyaları çoğu zaman .gitignore yazıldıktan SONRA yerine konur.
/// Bu yüzden var olan dosyalara değil desenlere bakıyoruz: açık kapıyı,
/// içeri bir şey girmeden önce fark etmek gerek.
const List<SecretKind> secretKinds = [
  SecretKind('ios/fastlane/AuthKey_FORGEPROBE.p8',
      'App Store Connect API anahtarı (.p8)', '*.p8'),
  SecretKind('android/fastlane/play-store-credentials.json',
      'Google Play servis hesabı anahtarı', '**/fastlane/play-store-credentials.json'),
  SecretKind('.env', 'Ortam değişkenleri (.env)', '.env'),
  SecretKind('android/key.properties', 'Android imzalama parolaları', 'key.properties'),
  SecretKind('android/app/upload-keystore.jks', 'Android anahtar deposu', '*.jks'),
  SecretKind('android/app/upload.keystore', 'Android anahtar deposu (.keystore)',
      '*.keystore'),
];

/// Git tarafından yok sayılmayan sır türleri.
///
/// Proje bir git deposu içinde değilse ya da git kurulu değilse `null` —
/// denetim yapılamadı demektir, "sorun yok" demek değil.
List<SecretKind>? unprotectedSecrets(FlutterProject p) {
  final unprotected = <SecretKind>[];

  for (final kind in secretKinds) {
    final io.ProcessResult result;
    try {
      result = io.Process.runSync(
        'git',
        ['check-ignore', '-q', kind.probe],
        workingDirectory: p.root,
      );
    } on io.ProcessException {
      return null; // git kurulu değil.
    }
    // 0: yok sayılıyor, 1: sayılmıyor, 128: git deposu değil.
    if (result.exitCode == 128) return null;
    if (result.exitCode == 1) unprotected.add(kind);
  }

  return unprotected;
}

Finding? _secretsNotIgnored(FlutterProject p) {
  final unprotected = unprotectedSecrets(p);
  if (unprotected == null || unprotected.isEmpty) return null;

  final labels = unprotected.map((k) => k.label).toSet().join(', ');
  final patterns = unprotected.map((k) => '  ${k.pattern}').toSet().join('\n');

  return Finding(
    id: 'secrets-not-ignored',
    severity: Severity.blocker,
    platform: Platform.both,
    title: 'Sır dosyaları .gitignore ile korunmuyor: $labels',
    why: 'Bu dosyalar depoya girerse imzalama anahtarlarınız ve mağaza '
        'erişim bilgileriniz açığa çıkar. Depo özel olsa bile geri alınamaz: '
        'git geçmişinden silinse dahi anahtarların iptal edilip yeniden '
        'üretilmesi gerekir. Üstelik dosyalar çoğu zaman .gitignore '
        'yazıldıktan sonra yerine konduğu için açık, bir şey sızana kadar '
        'fark edilmez.',
    fix: '.gitignore dosyasına ekleyin:\n'
        '$patterns\n'
        'Doğrulamak için:  git check-ignore -v <dosya>',
    autoFixable: true,
  );
}


Finding? _bundleIdMatch(FlutterProject p) {
  final android = p.androidApplicationId;
  final ios = p.iosBundleId;
  if (android == null || ios == null) return null;
  if (ios.contains(r'$(')) return null; // değişkenle tanımlanmış
  if (android == ios) return null;

  return Finding(
    id: 'bundle-id-mismatch',
    severity: Severity.warning,
    platform: Platform.both,
    title: 'Paket kimlikleri farklı: Android "$android", iOS "$ios"',
    why: 'İki mağazada farklı kimlik kullanmak zorunda değilsiniz; farklı '
        'olması derin bağlantı, analitik ve yayın betiklerinde karışıklık '
        'yaratır.',
    fix: 'Bilinçli bir tercih değilse ikisini eşitleyin.',
  );
}

Finding? _defaultBundleId(FlutterProject p) {
  final id = p.androidApplicationId ?? p.iosBundleId;
  if (id == null) return null;
  if (!id.startsWith('com.example')) return null;

  return Finding(
    id: 'default-bundle-id',
    severity: Severity.blocker,
    platform: Platform.both,
    title: 'Paket kimliği hâlâ varsayılan: "$id"',
    why: 'Apple ve Google "com.example" ile başlayan kimliği kabul etmez.',
    fix: 'Kendi alan adınıza göre değiştirin (ör. com.sirketiniz.uygulama). '
        'Bu değer yayınlandıktan sonra DEĞİŞTİRİLEMEZ.',
  );
}

Finding? _launcherIcon(FlutterProject p) {
  if (!p.hasAndroid) return null;
  // Flutter'ın varsayılan ikonu bu dosyadır; değiştirilmediyse boyutu
  // şablonla aynı kalır. Basit ve yeterli gösterge: özel ikon üretimi
  // yapılandırılmış mı?
  final pubspec = p.pubspec ?? '';
  if (pubspec.contains('flutter_launcher_icons')) return null;

  return const Finding(
    id: 'default-launcher-icon',
    severity: Severity.warning,
    platform: Platform.both,
    title: 'Özel uygulama ikonu yapılandırılmamış',
    why: 'Varsayılan Flutter logosuyla yayınlanan uygulama App Store '
        'incelemesinde reddedilir ve Play Store\'da kurumsal görünmez.',
    fix: 'flutter_launcher_icons paketini ekleyip assets/icon/icon.png '
        'dosyanızdan tüm boyutları üretin.',
  );
}

Finding? _appDescription(FlutterProject p) {
  final pubspec = p.pubspec ?? '';
  if (!pubspec.contains('A new Flutter project')) return null;

  return const Finding(
    id: 'default-description',
    severity: Severity.info,
    platform: Platform.both,
    title: 'pubspec.yaml açıklaması hâlâ şablon metni',
    why: 'Küçük bir ayrıntı ama projenin elden geçirilmediğinin işareti.',
    fix: 'description alanını uygulamanızı anlatan bir cümleyle değiştirin.',
    autoFixable: false,
  );
}
