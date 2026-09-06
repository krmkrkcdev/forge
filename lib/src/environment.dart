import 'dart:io' as io;

import 'package:path/path.dart' as p;

import 'finding.dart';

/// Makine ortamı denetimleri.
///
/// Proje dosyaları kusursuz olsa bile yayın, kurulu araç zinciri yüzünden
/// durabilir. Bu denetimler bilinçli olarak `forge doctor` çıktısının içinde
/// duruyor — ayrı bir bayrağa konsaydı tam da unutulacağı yerde olurdu.
typedef EnvCheck = Finding? Function();

const List<EnvCheck> allEnvironmentChecks = [
  _iosSdkVersion,
  _distributionCertificate,
  _utf8Locale,
  _staleGlobalInstall,
];

/// App Store Connect'in kabul ettiği en düşük iOS SDK ana sürümü.
///
/// Apple bu eşiği periyodik olarak yükseltir; yükselttiğinde burayı
/// güncelleyin. Nisan 2025'ten beri yürürlükte olan değer 18'dir
/// (Xcode 16 ile gelir).
const int minimumIosSdkMajor = 18;

List<Finding> runEnvironmentChecks() {
  final findings = <Finding>[];
  for (final check in allEnvironmentChecks) {
    final finding = check();
    if (finding != null) findings.add(finding);
  }
  findings.sort((a, b) => a.severity.index.compareTo(b.severity.index));
  return findings;
}

/// Komutu çalıştırır; komut yoksa ya da hata verirse `null`.
String? _run(String executable, List<String> arguments) {
  try {
    final result = io.Process.runSync(executable, arguments);
    if (result.exitCode != 0) return null;
    return (result.stdout as String).trim();
  } on io.ProcessException {
    return null;
  }
}

Finding? _iosSdkVersion() {
  // iOS derlemesi yalnızca macOS'ta yapılır; başka yerde bu denetim anlamsız.
  if (!io.Platform.isMacOS) return null;

  final version = _run('xcrun', ['--sdk', 'iphoneos', '--show-sdk-version']);
  if (version == null) return null; // Xcode kurulu değil; başka bir sorun.

  final major = int.tryParse(version.split('.').first);
  if (major == null || major >= minimumIosSdkMajor) return null;

  return Finding(
    id: 'ios-sdk-too-old',
    severity: Severity.blocker,
    platform: Platform.ios,
    title: 'Kurulu iOS SDK sürümü mağaza için çok eski: $version',
    why: 'App Store Connect, en az iOS $minimumIosSdkMajor SDK ile üretilmemiş '
        'paketleri reddeder. Bunu ancak tam bir derleme ve yükleme turunu '
        'harcadıktan sonra öğrenirsiniz. Ayrıca güncel paketler yeni SDK '
        'API\'lerini kullandığı için derleme daha en baştan da kırılabilir.',
    fix: 'Xcode\'u App Store üzerinden güncelleyin. Yeni Xcode sürümleri '
        'genellikle daha yeni bir macOS ister; önce işletim sistemini '
        'yükseltmeniz gerekebilir. Xcode 16 ve sonrasında simülatör '
        'çalışma zamanları ayrı indirilir: Settings → Components.',
  );
}

Finding? _distributionCertificate() {
  if (!io.Platform.isMacOS) return null;

  final identities = _run('security', ['find-identity', '-v', '-p', 'codesigning']);
  if (identities == null) return null;

  if (identities.contains('Apple Distribution') ||
      identities.contains('iPhone Distribution')) {
    return null;
  }

  return const Finding(
    id: 'ios-no-distribution-certificate',
    severity: Severity.blocker,
    platform: Platform.ios,
    title: 'Apple Distribution sertifikası yok',
    why: 'Mağaza yüklemesi dağıtım kimliği ister. Sertifika yoksa arşiv '
        'geliştirme kimliğiyle imzalanır ve paketleme "no provisioning '
        'profile mapping was provided" hatasıyla durur. Bu mesaj gerçek '
        'sebebi söylemediği için teşhisi zordur; üstelik hatayı ancak tam '
        'bir derleme turunu harcadıktan sonra görürsünüz.',
    fix: 'Xcode → Settings → Accounts → hesabınızı seçin → Manage '
        'Certificates → sol alt "+" → Apple Distribution. Yalnızca bir kez '
        'yapılır.',
  );
}

Finding? _utf8Locale() {
  if (!io.Platform.isMacOS) return null;

  final env = io.Platform.environment;
  final locale = env['LC_ALL'] ?? env['LANG'] ?? '';
  if (locale.toUpperCase().contains('UTF-8')) return null;

  return const Finding(
    id: 'locale-not-utf8',
    severity: Severity.warning,
    platform: Platform.both,
    title: 'LANG/LC_ALL tanımsız ya da UTF-8 değil',
    why: 'CocoaPods bu durumda "Unicode Normalization not appropriate for '
        'ASCII-8BIT" hatasıyla çöker, fastlane de çalışmayı reddeder. Hiçbiri '
        'sorunun locale olduğunu söylemez; teşhis edilmesi en can sıkıcı '
        'hatalardan biridir.',
    fix: 'Kabuk yapılandırmanıza (~/.zshrc) ekleyin:\n'
        '  export LANG=en_US.UTF-8\n'
        '  export LC_ALL=en_US.UTF-8',
  );
}

// ------------------------------------------------- kurulu forge güncel mi

/// `dart pub global list` çıktısından, yoldan kurulmuş forge'un kaynak
/// dizinini okur. Yoldan kurulmamışsa (hosted/git) `null`.
String? _globallyActivatedForgePath() {
  final output = _run('dart', ['pub', 'global', 'list']);
  if (output == null) return null;
  final match = RegExp(r'^forge \S+ at path "(.+)"$', multiLine: true)
      .firstMatch(output);
  return match?.group(1);
}

/// Kurulu anlık görüntünün (snapshot) tarihi; yoksa `null`.
///
/// **Anlık görüntü PUB_CACHE'te değil, PROJENİN içinde durur.** Dart 3.x,
/// yoldan kurulan paketi `<kaynak>/.dart_tool/pub/bin/<paket>/` altına
/// derler; PUB_CACHE'te yalnızca ona işaret eden bir kabuk sarmalayıcısı ve
/// `pubspec.lock` bulunur. Bu ayrım can yakıcıdır: `dart pub global activate`
/// sarmalayıcıyı ve kilidi tazeler ama anlık görüntüyü YERİNDE BIRAKIR, yani
/// kurulum "başarılı" der ve komut aylar öncesinin kodunu çalıştırmaya devam
/// eder. Gerçekten yaşandı — bir ay boyunca ağustos kodu çalıştı.
///
/// Hiç anlık görüntü yoksa `null` döner ve bu iyi haberdir: sarmalayıcı o
/// durumda `dart pub global run` ile her çağrıda derler, dolayısıyla kurulum
/// eski kalamaz.
DateTime? installedForgeSnapshotDate({
  required String sourceDir,
  String? pubCache,
}) {
  final home = io.Platform.environment['HOME'];
  final cache = pubCache ??
      io.Platform.environment['PUB_CACHE'] ??
      (home == null ? null : p.join(home, '.pub-cache'));

  final candidates = <io.Directory>[
    io.Directory(p.join(sourceDir, '.dart_tool', 'pub', 'bin', 'forge')),
    // Eski SDK'lar PUB_CACHE altına yazıyordu; makinede kalmış olabilir.
    if (cache != null)
      io.Directory(p.join(cache, 'global_packages', 'forge', 'bin')),
  ];

  DateTime? newest;
  for (final dir in candidates) {
    if (!dir.existsSync()) continue;
    for (final entity in dir.listSync()) {
      if (entity is! io.File || !entity.path.endsWith('.snapshot')) continue;
      final modified = entity.statSync().modified;
      if (newest == null || modified.isAfter(newest)) newest = modified;
    }
  }
  return newest;
}

/// Kaynak dizindeki en yeni değişiklik tarihi.
///
/// Yalnızca kurulumu etkileyen dosyalara bakar: `lib/`, `bin/` ve
/// `pubspec.yaml`. Şablonlar `lib/src/templates/bundle.dart` içine gömüldüğü
/// için assets/ ayrıca taranmaz — gömme adımı atlanmışsa onu `dart test`
/// yakalar.
DateTime? newestForgeSourceChange(String sourceDir) {
  DateTime? newest;

  void consider(io.FileSystemEntity entity) {
    if (entity is! io.File) return;
    if (!entity.path.endsWith('.dart') &&
        p.basename(entity.path) != 'pubspec.yaml') {
      return;
    }
    // DİKKAT: statSync() var olmayan dosya için istisna ATMAZ; type'ı
    // notFound, modified'ı 1970 olan bir kayıt döndürür. Bu kontrol olmadan
    // "dosya yok" ile "dosya çok eski" aynı şeye dönüşür ve işlev, kaynağı
    // boş dizinde bile bir tarih uydurur.
    final stat = entity.statSync();
    if (stat.type == io.FileSystemEntityType.notFound) return;
    final modified = stat.modified;
    if (newest == null || modified.isAfter(newest!)) newest = modified;
  }

  for (final relative in ['lib', 'bin']) {
    final dir = io.Directory(p.join(sourceDir, relative));
    if (!dir.existsSync()) continue;
    for (final entity in dir.listSync(recursive: true)) {
      consider(entity);
    }
  }
  consider(io.File(p.join(sourceDir, 'pubspec.yaml')));

  return newest;
}

/// Kurulu forge, kaynağın gerisinde mi?
///
/// Gerçek bir olaydan doğdu: `checks.dart` içine yeni bir engel eklendi,
/// `deploy.sh` yayın öncesi `forge doctor` çağırdı — ama PATH'teki forge eski
/// anlık görüntüydü ve yeni kural hiç çalışmadı. Denetim sessizce "temiz"
/// dedi ve sürüm o hatayla mağazaya gitti.
///
/// Bu denetim yalnızca forge KAYNAKTAN çalışırken (panel, `dart run`) işe
/// yarar; eski global kopya bu kuralı zaten içermez. Panel forge'u hep
/// kaynaktan çalıştırdığı için uyarıyı orada görürsünüz.
Finding? _staleGlobalInstall() {
  final source = _globallyActivatedForgePath();
  if (source == null) return null; // yoldan kurulmamış: kıyaslanacak kaynak yok

  final installed = installedForgeSnapshotDate(sourceDir: source);
  if (installed == null) return null; // anlık görüntü yok: her çağrıda derlenir

  final changed = newestForgeSourceChange(source);
  if (changed == null || !changed.isAfter(installed)) return null;

  return Finding(
    id: 'forge-install-stale',
    severity: Severity.warning,
    platform: Platform.both,
    title: 'PATH\'teki forge kaynaktan eski '
        '(kurulum ${_ago(installed)}, kaynak ${_ago(changed)} değişti)',
    why: 'Kurulum sırasında derlenen anlık görüntü çalışıyor; kaynağı '
        'düzenlemek onu güncellemez. Daha kötüsü: `dart pub global activate` '
        'sarmalayıcıyı tazeler ama anlık görüntüyü YERİNDE BIRAKIR, yani '
        'kurulum "başarılı" der ve komut yine eski kodu çalıştırır. '
        'deploy.sh yayın öncesi PATH\'teki forge\'u çağırdığı için yeni '
        'eklenen denetimler HİÇ çalışmaz ve çıktı yanıltıcı biçimde "temiz" '
        'görünür. Gerçekten yaşandı: bir ay boyunca eski kod çalıştı, yeni '
        'eklenen engel kuralları hiç denetlenmedi.',
    fix: 'Anlık görüntüyü SİLİP yeniden kurun — yalnızca activate yetmez:\n'
        '  rm -rf $source/.dart_tool/pub/bin/forge\n'
        '  dart pub global activate --source path $source',
  );
}

/// "3 gün önce" gibi kısa bir ifade.
String _ago(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 60) return '${diff.inMinutes} dk önce';
  if (diff.inHours < 24) return '${diff.inHours} saat önce';
  return '${diff.inDays} gün önce';
}
