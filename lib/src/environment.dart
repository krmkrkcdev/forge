import 'dart:io' as io;

import 'finding.dart';

/// Makine ortamı denetimleri.
///
/// Proje dosyaları kusursuz olsa bile yayın, kurulu araç zinciri yüzünden
/// durabilir. Bu denetimler bilinçli olarak `forge doctor` çıktısının içinde
/// duruyor — ayrı bir bayrağa konsaydı tam da unutulacağı yerde olurdu.
typedef EnvCheck = Finding? Function();

const List<EnvCheck> allEnvironmentChecks = [
  _iosSdkVersion,
  _utf8Locale,
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
