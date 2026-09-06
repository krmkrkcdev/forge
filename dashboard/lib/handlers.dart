import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:forge/src/checks.dart';
import 'package:forge/src/compose.dart';
import 'package:forge/src/environment.dart';
import 'package:forge/src/native_patch.dart';
// dart:io'nun Platform sınıfını (Platform.script) gölgelememesi için
// finding.dart'ın Platform enum'unu gizliyoruz; buradaki kod enum'u tip
// adıyla kullanmıyor, yalnızca f.platform üzerinden erişiyor.
import 'package:forge/src/finding.dart' hide Platform;
import 'package:forge/src/project.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';

/// Panelin bütün uç noktaları.
///
/// İki tür iş var ve bilinçli olarak farklı yürür:
///  * Denetim (doctor) — hızlı ve saf, forge kütüphanesi doğrudan çağrılır.
///  * Değiştiren işler (fix, new, deploy) — alt süreç olarak başlatılır ve
///    çıktısı canlı (SSE) akıtılır; çünkü dakikalarca sürebilirler ve
///    kullanıcının ne olduğunu anlık görmesi gerekir.
class Handlers {
  Handlers({required this.forgeRoot, required this.projectsBase});

  final String forgeRoot;
  final String projectsBase;

  /// Aynı anda tek bir değiştiren iş. İki yayının çakışması, yarısı yüklenmiş
  /// bir sürümden çok daha kötü sonuçlar doğurabilir.
  bool _busy = false;

  String get _forgeEntry => p.join(forgeRoot, 'bin', 'forge.dart');
  String get _webDir => p.join(forgeRoot, 'dashboard', 'web');

  Future<Response> router(Request request) async {
    final path = request.url.path;
    try {
      switch (path) {
        case 'api/projects':
          return _projects();
        case 'api/doctor':
          return _doctor(request);
        case 'api/readiness':
          return _readiness(request);
        case 'api/fix':
          return _fix(request);
        case 'api/update':
          return _update(request);
        case 'api/analyze':
          return _analyze(request);
        case 'api/forge-reinstall':
          return _forgeReinstall();
        case 'api/new':
          return _new(request);
        case 'api/deploy':
          return _deploy(request);
        case 'api/server-deploy':
          return _serverDeploy(request);
        case 'api/server-update':
          return _serverUpdate(request);
        case 'api/config':
          return await _config(request);
        case 'api/config/upload':
          return await _configUpload(request);
        case 'api/account':
          return await _account(request);
        case 'api/account/upload':
          return await _accountUpload(request);
        case 'api/icon/upload':
          return await _iconUpload(request);
        case 'api/icon':
          return _icon(request);
        case 'api/guide':
          return await _guide(request);
        case 'api/github/status':
          return _githubStatus();
        case 'api/github/login':
          return _githubLogin();
        default:
          return _static(path);
      }
    } catch (e) {
      return _json({'error': '$e'}, status: 500);
    }
  }

  // ---------------------------------------------------------- projeler

  Response _projects() {
    final base = Directory(projectsBase);
    final found = <Map<String, dynamic>>[];
    if (base.existsSync()) {
      for (final entity in base.listSync()) {
        if (entity is! Directory) continue;
        // Hem kök hem forge new düzeni (app/): ikisini de dener.
        for (final candidate in [entity.path, p.join(entity.path, 'app')]) {
          final info = _describe(candidate);
          if (info != null) {
            found.add(info);
            break;
          }
        }
      }
    }
    found.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
    return _json({'base': projectsBase, 'projects': found});
  }

  /// Bir dizinin yayınlanabilir bir Flutter projesi olup olmadığını anlatır;
  /// değilse `null`.
  Map<String, dynamic>? _describe(String dir) {
    final pubspec = File(p.join(dir, 'pubspec.yaml'));
    if (!pubspec.existsSync()) return null;
    final content = pubspec.readAsStringSync();
    if (!content.contains('sdk: flutter')) return null;

    final project = FlutterProject(dir);
    return {
      'name': p.basename(p.dirname(dir)) == 'app'
          ? p.basename(dir)
          : p.basename(dir),
      'label': _prettyName(dir, project),
      'path': dir,
      'appName': project.appName,
      'version': project.versionValue,
      'hasIos': project.hasIos,
      'hasAndroid': project.hasAndroid,
      'hasDeploy': File(p.join(dir, 'deploy.sh')).existsSync(),
      'usesAds': project.usesAds,
    };
  }

  String _prettyName(String dir, FlutterProject project) {
    // forge new düzeninde proje app/ altında; kullanıcıya deponun adını
    // göstermek daha anlamlı.
    final repo = p.basename(dir) == 'app'
        ? p.basename(p.dirname(dir))
        : p.basename(dir);
    return repo;
  }

  // ------------------------------------------------------------ doctor

  Response _doctor(Request request) {
    final path = request.url.queryParameters['path'];
    if (path == null || path.isEmpty) {
      return _json({'error': 'path parametresi gerekli'}, status: 400);
    }
    final project = FlutterProject.locate(path);
    if (project == null) {
      return _json({'error': 'Flutter projesi bulunamadı: $path'}, status: 404);
    }

    final findings = [
      for (final f in runChecks(project)) _findingJson(f, 'proje'),
      for (final f in runEnvironmentChecks()) _findingJson(f, 'ortam'),
    ];
    final blockers = findings.where((f) => f['severity'] == 'blocker').length;
    final warnings = findings.where((f) => f['severity'] == 'warning').length;

    return _json({
      'project': project.appName ?? p.basename(project.root),
      'root': project.root,
      'findings': findings,
      'summary': {
        'blockers': blockers,
        'warnings': warnings,
        'info': findings.length - blockers - warnings,
        'autoFixable': findings.where((f) => f['autoFixable'] == true).length,
        'ready': blockers == 0,
      },
    });
  }

  Map<String, dynamic> _findingJson(Finding f, String source) => {
    'id': f.id,
    'severity': f.severity.name, // blocker | warning | info
    'severityLabel': f.severity.label,
    'platform': f.platform.name, // ios | android | both
    'title': f.title,
    'why': f.why,
    'fix': f.fix,
    'autoFixable': f.autoFixable,
    'source': source,
  };

  // ---------------------------------------------------- yayına hazırlık

  /// "Yayına ne kaldı?" — iOS ve Android yolları AYRI değerlendirilir:
  /// Android'de eksik bir anahtar iOS yayınını bekletmemeli. Ortak işler
  /// (ikon) ayrı döner; her platformun kendi kapı listesi ve hükmü vardır.
  Response _readiness(Request request) {
    final path = request.url.queryParameters['path'];
    if (path == null || path.isEmpty) {
      return _json({'error': 'path gerekli'}, status: 400);
    }
    final project = FlutterProject.locate(path) ?? FlutterProject(path);

    final findings = [...runChecks(project), ...runEnvironmentChecks()];
    // "both" bulgular iki yolu da ilgilendirir (ör. sır sızıntısı, sürüm).
    List<Finding> byPlat(String plat) => findings
        .where((f) => f.platform.name == plat || f.platform.name == 'both')
        .toList();

    final env = _readEnv(p.join(path, '.env'));
    final account = _readAccount();
    bool has(String k) =>
        (env[k]?.isNotEmpty ?? false) || (account[k]?.isNotEmpty ?? false);
    bool realUnit(String k) {
      final v = env[k] ?? '';
      return v.isNotEmpty && !v.contains(_admobTestPub);
    }

    Map<String, dynamic> doctorGate(String plat) {
      final list = byPlat(plat);
      final b = list.where((f) => f.severity == Severity.blocker).length;
      final w = list.where((f) => f.severity == Severity.warning).length;
      return {
        'label': 'Mağaza denetimi',
        'status': b > 0 ? 'block' : (w > 0 ? 'warn' : 'ok'),
        'hint': '$b engel · $w uyarı',
        'jump': 'doctor',
      };
    }

    // ------------------------------------------------------------ iOS yolu
    final ios = <Map<String, dynamic>>[];
    if (project.hasIos) {
      ios.add(doctorGate('ios'));
      final ascOk =
          has('ASC_KEY_ID') && has('ASC_ISSUER_ID') && has('ASC_KEY_FILEPATH');
      ios.add({
        'label': 'App Store Connect anahtarı',
        'status': ascOk ? 'ok' : 'todo',
        'hint': ascOk ? 'girildi' : 'Key ID / Issuer / .p8 eksik',
        'jump': 'account',
      });
      if (project.usesAds) {
        final app = _readNativeAdmob(path, 'ios') ?? '';
        final appReal = app.isNotEmpty && !app.contains(_admobTestPub);
        ios.add({
          'label': 'AdMob uygulama kimliği',
          'status': appReal ? 'ok' : 'warn',
          'hint': appReal ? 'gerçek' : 'test kimliği — gelir yok',
          'jump': 'config',
        });
        final unitsOk =
            realUnit('ADMOB_BANNER_IOS') && realUnit('ADMOB_INTERSTITIAL_IOS');
        ios.add({
          'label': 'Reklam birim kimlikleri',
          'status': unitsOk ? 'ok' : 'warn',
          'hint': unitsOk ? 'girildi' : 'boş/test — gelir yok',
          'jump': 'config',
        });
      }
    }

    // -------------------------------------------------------- Android yolu
    final android = <Map<String, dynamic>>[];
    if (project.hasAndroid) {
      android.add(doctorGate('android'));
      final signingOk = File(
        p.join(path, 'android', 'key.properties'),
      ).existsSync();
      android.add({
        'label': 'Sürüm imzalama (key.properties)',
        'status': signingOk ? 'ok' : 'todo',
        'hint': signingOk
            ? 'kurulu'
            : 'android/key.properties.example → key.properties',
        'jump': 'doctor',
      });
      android.add({
        'label': 'Google Play anahtarı',
        'status': has('GOOGLE_PLAY_JSON_KEY') ? 'ok' : 'todo',
        'hint': has('GOOGLE_PLAY_JSON_KEY')
            ? 'girildi'
            : 'service account JSON eksik',
        'jump': 'account',
      });
      if (project.usesAds) {
        final app = _readNativeAdmob(path, 'android') ?? '';
        final appReal = app.isNotEmpty && !app.contains(_admobTestPub);
        android.add({
          'label': 'AdMob uygulama kimliği',
          'status': appReal ? 'ok' : 'warn',
          'hint': appReal ? 'gerçek' : 'test kimliği — gelir yok',
          'jump': 'config',
        });
        final unitsOk =
            realUnit('ADMOB_BANNER_ANDROID') &&
            realUnit('ADMOB_INTERSTITIAL_ANDROID');
        android.add({
          'label': 'Reklam birim kimlikleri',
          'status': unitsOk ? 'ok' : 'warn',
          'hint': unitsOk ? 'girildi' : 'boş/test — gelir yok',
          'jump': 'config',
        });
      }
    }

    // -------------------------------------------------------------- ortak
    final common = <Map<String, dynamic>>[
      {
        'label': 'Uygulama ikonu',
        'status': File(p.join(path, 'assets', 'icon', 'icon.png')).existsSync()
            ? 'ok'
            : 'todo',
        'hint': 'assets/icon/icon.png',
        'jump': 'icon',
      },
    ];

    Map<String, dynamic> verdict(List<Map<String, dynamic>> gates) {
      final blocks = gates.where((g) => g['status'] == 'block').length;
      final todo = gates.where((g) => g['status'] != 'ok').length;
      return {'blockers': blocks, 'remaining': todo, 'ready': blocks == 0};
    }

    return _json({
      'common': common,
      'platforms': {
        if (project.hasIos)
          'ios': {'title': '🍎 iOS', 'gates': ios, ...verdict(ios)},
        if (project.hasAndroid)
          'android': {
            'title': '🤖 Android',
            'gates': android,
            ...verdict(android),
          },
      },
    });
  }

  /// Google'ın test yayıncı kimliği — gerçek gelirle karışmasın.
  static const _admobTestPub = 'ca-app-pub-3940256099942544';

  // ------------------------------------------------------- yol haritası

  /// Yol haritasındaki ELLE yapılan adımların (ASC kaydı, App Privacy,
  /// testçi ekleme…) işaret durumu. Panel otomatik izleyemediği adımları
  /// kullanıcı işaretler; ~/.forge/progress.json'da proje yoluna göre saklanır
  /// ki panel yeniden başlasa da ilerleme kaybolmasın.
  Future<Response> _guide(Request request) async {
    final path = request.url.queryParameters['path'];
    if (path == null || path.isEmpty) {
      return _json({'error': 'path gerekli'}, status: 400);
    }
    final file = File(p.join(_accountDir, 'progress.json'));
    Map<String, dynamic> all = {};
    if (file.existsSync()) {
      try {
        all = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      } catch (_) {}
    }

    if (request.method == 'POST') {
      final data =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final key = data['key'] as String?;
      if (key == null || key.isEmpty) {
        return _json({'error': 'key gerekli'}, status: 400);
      }
      final proj = ((all[path] as Map?) ?? {}).cast<String, dynamic>();
      if (data['done'] == true) {
        proj[key] = true;
      } else {
        proj.remove(key);
      }
      all[path] = proj;
      Directory(_accountDir).createSync(recursive: true);
      file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(all));
      return _json({'ok': true});
    }

    return _json({'progress': (all[path] as Map?) ?? {}});
  }

  // --------------------------------------------------------------- fix

  Response _fix(Request request) {
    final q = request.url.queryParameters;
    final path = q['path'];
    if (path == null || path.isEmpty) {
      return _sseError('path parametresi gerekli');
    }
    final apply = q['apply'] == '1';
    // Uygulanan düzeltmeler diske yazar; varsayılan deneme çalıştırmasıdır.
    final args = [
      'run',
      _forgeEntry,
      'fix',
      '--path',
      path,
      if (!apply) '--dry-run',
    ];
    return _spawn('dart', args, workingDir: forgeRoot);
  }

  // --------------------------------------------------------------- ikon

  /// Yüklenen görseli projenin assets/icon dizinine yazar (ikon + adaptive ön
  /// plan olarak aynı görsel). Üretimi /api/icon (SSE) yapar.
  Future<Response> _iconUpload(Request request) async {
    final path = request.url.queryParameters['path'];
    if (path == null || path.isEmpty) {
      return _json({'error': 'path parametresi gerekli'}, status: 400);
    }
    if (!File(p.join(path, 'pubspec.yaml')).existsSync()) {
      return _json({'error': 'Proje bulunamadı: $path'}, status: 404);
    }
    final dir = Directory(p.join(path, 'assets', 'icon'))
      ..createSync(recursive: true);
    final bytes = await request.read().expand((c) => c).toList();
    if (bytes.isEmpty) {
      return _json({'error': 'Boş görsel'}, status: 400);
    }
    File(p.join(dir.path, 'icon.png')).writeAsBytesSync(bytes);
    File(p.join(dir.path, 'icon_foreground.png')).writeAsBytesSync(bytes);
    return _json({'ok': true});
  }

  /// assets/icon'daki görselden ikon ve açılış ekranını üretir (canlı akış).
  /// Görsel önce /api/icon/upload ile konmuş olmalı.
  Response _icon(Request request) {
    final path = request.url.queryParameters['path'];
    if (path == null || path.isEmpty) {
      return _sseError('path parametresi gerekli');
    }
    if (!File(p.join(path, 'assets', 'icon', 'icon.png')).existsSync()) {
      return _sseError('Önce bir görsel yükleyin.');
    }
    return _run([
      _Step(
        'dart',
        ['run', 'flutter_launcher_icons'],
        path,
        label: 'Uygulama ikonu',
      ),
      _Step(
        'dart',
        ['run', 'flutter_native_splash:create'],
        path,
        label: 'Açılış ekranı',
      ),
    ]);
  }

  // ------------------------------------------------------------ güncelle

  /// Projenin bağımlılıklarını tazeler (flutter pub get). `upgrade=1` verilirse
  /// sürümleri de yükseltir (flutter pub upgrade). Diske yazan bir iştir ama
  /// mağazaya dönük değildir; onay istemez.
  Response _update(Request request) {
    final q = request.url.queryParameters;
    final path = q['path'];
    if (path == null || path.isEmpty) {
      return _sseError('path parametresi gerekli');
    }
    if (!File(p.join(path, 'pubspec.yaml')).existsSync()) {
      return _sseError('pubspec.yaml bulunamadı: $path');
    }
    final upgrade = q['upgrade'] == '1';
    return _spawn('flutter', [
      'pub',
      upgrade ? 'upgrade' : 'get',
    ], workingDir: path);
  }

  // ------------------------------------------------------------- analiz

  /// Bağımlılıkları çözer ve `flutter analyze` çalıştırır.
  ///
  /// forge doctor'ın bakmadığı yere bakar: kodun kendisine. Derleme hatasını
  /// yayın akışının ortasında öğrenmek dakikalara mal olur; burada saniyeler
  /// sürer.
  Response _analyze(Request request) {
    final path = request.url.queryParameters['path'];
    if (path == null || path.isEmpty) {
      return _sseError('path parametresi gerekli');
    }
    if (!File(p.join(path, 'pubspec.yaml')).existsSync()) {
      return _sseError('pubspec.yaml bulunamadı: $path');
    }
    // forge analyze yerine doğrudan flutter çağrılıyor: panel forge'u zaten
    // kaynaktan çalıştırıyor, araya bir Dart süreci daha koymanın faydası yok
    // ve adımlar ayrı ayrı etiketlendiğinde hangisinin patladığı görünür.
    return _run([
      _Step('flutter', ['pub', 'get'], path, label: 'Bağımlılıklar'),
      _Step('flutter', ['analyze'], path, label: 'Statik analiz'),
    ]);
  }

  // ------------------------------------------------------ forge kurulumu

  /// PATH'teki forge'u bu depodaki kaynaktan yeniden kurar.
  ///
  /// `dart pub global activate` kaynağı derleyip anlık görüntü olarak saklar;
  /// sonradan kaynağı düzenlemek o görüntüyü güncellemez. deploy.sh yayın
  /// öncesi PATH'teki forge'u çağırdığı için, yeni eklenen denetimler eski
  /// kurulumda HİÇ çalışmaz ve çıktı yanıltıcı biçimde "temiz" görünür.
  Response _forgeReinstall() {
    // Anlık görüntü PUB_CACHE'te değil, BU DEPONUN .dart_tool dizinindedir
    // (Dart 3.x, yoldan kurulan paketler). `activate` sarmalayıcıyı tazeler
    // ama bu dosyaya dokunmaz: silinmezse kurulum "başarılı" der ve komut
    // yine eski kodu çalıştırır. Bir ay boyunca öyle oldu.
    final snapshots = Directory(p.join(forgeRoot, '.dart_tool', 'pub', 'bin', 'forge'));
    if (snapshots.existsSync()) snapshots.deleteSync(recursive: true);

    return _spawn(
      'dart',
      ['pub', 'global', 'activate', '--source', 'path', forgeRoot],
      workingDir: forgeRoot,
    );
  }

  // --------------------------------------------------------------- new

  Response _new(Request request) {
    final q = request.url.queryParameters;
    final name = q['name'];
    final org = q['org'];
    final parent = q['parent'];
    if (name == null || org == null || parent == null) {
      return _sseError('name, org ve parent parametreleri gerekli');
    }
    final appName = q['appName'];
    final description = q['description'];
    final backend = q['backend'] == '1';
    final github = q['github'] == '1';
    final visibility = q['visibility'] == 'public' ? '--public' : '--private';

    final steps = <_Step>[
      _Step(
        'dart',
        [
          'run',
          _forgeEntry,
          'new',
          name,
          '--org',
          org,
          if (appName != null && appName.isNotEmpty) ...['--app-name', appName],
          if (description != null && description.isNotEmpty) ...[
            '--description',
            description,
          ],
          if (backend) '--backend',
        ],
        // Proje, seçilen üst dizinin içine kurulur.
        parent,
        label: 'forge new',
      ),
    ];

    // GitHub'a bağlama: forge new zaten yerel bir git deposu kurup ilk
    // commit'i atıyor. `gh repo create --source ... --push`, o var olan
    // depodan GitHub'da yeni bir repo oluşturur, origin olarak ekler ve
    // gönderir. Sonuç: repo hesapta, yerel klasör GitHub dizininde, kod
    // yüklenmiş — "önce repo, sonra bağla" isteğinin karşılığı.
    if (github) {
      if (!_hasExecutable('gh')) {
        return _sseError(
          'gh (GitHub CLI) bulunamadı. Kurulum: brew install gh. GitHub '
          'olmadan oluşturmak için formdaki kutunun işaretini kaldırın.',
        );
      }
      if (Process.runSync('gh', [
            'auth',
            'status',
          ], environment: _localeFix).exitCode !=
          0) {
        return _sseError(
          'gh kurulu ama GitHub girişi yapılmamış. Kenar çubuğundaki '
          '"GitHub girişi yap" düğmesini kullanın ya da GitHub olmadan '
          'oluşturmak için formdaki kutunun işaretini kaldırın.',
        );
      }
      final projectDir = p.join(parent, name);
      steps.add(
        _Step(
          'gh',
          [
            'repo',
            'create',
            name,
            visibility,
            '--source',
            projectDir,
            '--remote',
            'origin',
            '--push',
            if (description != null && description.isNotEmpty) ...[
              '--description',
              description,
            ],
          ],
          parent,
          label: 'gh repo create (GitHub\'a bağla ve gönder)',
        ),
      );
    }

    return _run(steps);
  }

  // ------------------------------------------------------------- github

  /// GitHub CLI durumu: kurulu mu, giriş yapılmış mı, hangi hesapla?
  /// Panel bunu açılışta sorar; eksik varsa uyarı baştan görünür, proje
  /// oluşturma anına kalmaz.
  Response _githubStatus() {
    if (!_hasExecutable('gh')) {
      return _json({'installed': false, 'authenticated': false});
    }
    final res = Process.runSync('gh', [
      'auth',
      'status',
    ], environment: _localeFix);
    // gh sürümüne göre çıktı stdout'a da stderr'e de gidebiliyor.
    final out = '${res.stdout}\n${res.stderr}';
    final account = RegExp(r'account (\S+)').firstMatch(out)?.group(1);
    return _json({
      'installed': true,
      'authenticated': res.exitCode == 0,
      'account': ?account,
    });
  }

  /// `gh auth login --web` — terminalsiz cihaz akışı: gh tek seferlik kodu
  /// konsola basar ve doğrulamayı bekler; istemci github.com/login/device
  /// sayfasını açar, kullanıcı kodu oraya girer.
  Response _githubLogin() {
    if (!_hasExecutable('gh')) {
      return _sseError(
        'gh (GitHub CLI) kurulu değil. Terminalde: brew install gh',
      );
    }
    return _spawn('gh', [
      'auth',
      'login',
      '--web',
      '--hostname',
      'github.com',
      '--git-protocol',
      'https',
    ], workingDir: forgeRoot);
  }

  /// Çocuk süreçlere eklenecek yerel düzeltmesi. Sunucunun ortamında UTF-8
  /// yereli zaten varsa boş döner (kullanıcının değerine dokunulmaz); yoksa
  /// LANG/LC_ALL enjekte edilir. Process.start bu haritayı üst ortamın
  /// ÜZERİNE ekler.
  static final Map<String, String> _localeFix = (() {
    final env = Platform.environment;
    final locale = env['LC_ALL'] ?? env['LANG'] ?? '';
    if (locale.toUpperCase().contains('UTF-8')) return const <String, String>{};
    return const {'LANG': 'en_US.UTF-8', 'LC_ALL': 'en_US.UTF-8'};
  })();

  /// Bir çalıştırılabilir PATH'te var mı? (which/where ile ucuz kontrol.)
  bool _hasExecutable(String exe) {
    try {
      final which = Platform.isWindows ? 'where' : 'which';
      return Process.runSync(which, [exe]).exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------- yapılandırma

  /// HESAP düzeyi anahtarlar: aynı Apple/Play hesabını kullanan bütün
  /// uygulamalarda AYNIDIR. Bir kez "Hesap Varsayılanları"nda girilir, her yeni
  /// uygulamada otomatik gelir. Geri kalan her şey (bundle id, AdMob birim
  /// kimlikleri, API adresi) uygulamaya özeldir ve boş başlar.
  static const Set<String> _accountKeys = {
    'APPLE_TEAM_ID',
    'ASC_KEY_ID',
    'ASC_ISSUER_ID',
    'ASC_KEY_FILEPATH',
    'GOOGLE_PLAY_JSON_KEY',
    'MATCH_GIT_URL',
    'MATCH_PASSWORD',
    // Sunucu bilgileri de hesap düzeyidir: bütün uygulamalar aynı
    // makineye kurulur.
    'SERVER_HOST',
    'SERVER_USER',
    'SERVER_BASE_PATH',
  };

  /// Uygulamanın çalışması ve yayınlanması için gereken bütün anahtarların
  /// tanımı. `.env` dosyasının kaynağı buradadır: her alanın nereden alınacağı
  /// (help), ne olduğu (desc) ve sır mı / dosya mı olduğu tek yerde durur.
  ///
  /// Reklam UYGULAMA kimliği (ca-app-pub-…~…) bilinçli olarak burada değil:
  /// o `.env`'e değil Info.plist/AndroidManifest'e yazılır (ayrı bir adım).
  static const List<Map<String, dynamic>> _configGroups = [
    {
      'id': 'identity',
      'title': 'Kimlik',
      'note': 'Uygulamanın mağaza kimlikleri. Yayından sonra değişmez.',
      'fields': [
        {
          'key': 'APP_IDENTIFIER',
          'label': 'iOS bundle identifier',
          'placeholder': 'com.sirketiniz.uygulama',
          'desc': 'Xcode\'daki bundle id ile aynı olmalı.',
        },
        {
          'key': 'ANDROID_PACKAGE_NAME',
          'label': 'Android package name',
          'placeholder': 'com.sirketiniz.uygulama',
          'desc': 'build.gradle\'daki applicationId ile aynı.',
        },
        {
          'key': 'APPLE_TEAM_ID',
          'label': 'Apple Team ID',
          'placeholder': 'XXXXXXXXXX',
          'desc': 'Apple Developer hesabındaki 10 haneli takım kimliği.',
          'help': 'https://developer.apple.com/account#MembershipDetailsCard',
          'helpLabel': 'developer.apple.com › Membership',
        },
      ],
    },
    {
      'id': 'asc',
      'title': 'App Store Connect (iOS yayın)',
      'note': 'App Store\'a 2FA sormadan yükleme yapan API anahtarı.',
      'help': 'https://appstoreconnect.apple.com/access/integrations/api',
      'helpLabel': 'App Store Connect › Integrations › API anahtarı oluştur',
      'fields': [
        {'key': 'ASC_KEY_ID', 'label': 'Key ID', 'placeholder': 'XXXXXXXXXX'},
        {
          'key': 'ASC_ISSUER_ID',
          'label': 'Issuer ID',
          'placeholder': 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx',
        },
        {
          'key': 'ASC_KEY_FILEPATH',
          'label': 'API anahtar dosyası (.p8)',
          'file': true,
          'accept': '.p8',
          'dest': 'ios/fastlane',
          'desc': 'Oluştururken bir kez indirilir; kaybolursa yenisini üret.',
        },
      ],
    },
    {
      'id': 'play',
      'title': 'Google Play (Android yayın)',
      'note': 'Play Console\'a yükleme yapan servis hesabı anahtarı.',
      'help': 'https://play.google.com/console',
      'helpLabel': 'Play Console › Setup › API access › service account',
      'fields': [
        {
          'key': 'GOOGLE_PLAY_JSON_KEY',
          'label': 'Servis hesabı anahtarı (.json)',
          'file': true,
          'accept': '.json',
          'dest': 'android/fastlane',
        },
      ],
    },
    {
      'id': 'admob',
      'title': 'Reklam — AdMob birim kimlikleri',
      'note':
          'BOŞ bırakılırsa kod TEST reklamı gösterir (gelir sıfır). '
          'Gerçek kimlikle geliştirip kendi reklamına tıklamak hesabı kapatır.',
      'help': 'https://admob.google.com',
      'helpLabel': 'admob.google.com › Uygulamalar › Reklam birimleri',
      'fields': [
        {
          'key': 'ADMOB_BANNER_IOS',
          'label': 'Banner — iOS',
          'placeholder': 'ca-app-pub-…/…',
        },
        {
          'key': 'ADMOB_INTERSTITIAL_IOS',
          'label': 'Geçiş reklamı — iOS',
          'placeholder': 'ca-app-pub-…/…',
        },
        {
          'key': 'ADMOB_BANNER_ANDROID',
          'label': 'Banner — Android',
          'placeholder': 'ca-app-pub-…/…',
        },
        {
          'key': 'ADMOB_INTERSTITIAL_ANDROID',
          'label': 'Geçiş reklamı — Android',
          'placeholder': 'ca-app-pub-…/…',
        },
      ],
    },
    {
      'id': 'admob_app',
      'title': 'Reklam — Uygulama kimliği',
      'note':
          'ca-app-pub-…~… biçimindeki UYGULAMA kimliği (reklam BİRİMİ '
          'kimliğinden farklı, ~ işaretli). .env\'e değil doğrudan '
          'Info.plist ve AndroidManifest.xml\'e yazılır. TEST kimliğiyle '
          'yayınlanan uygulama çalışır ama HİÇ gelir getirmez.',
      'help': 'https://admob.google.com',
      'helpLabel':
          'admob.google.com › Uygulamalar (uygulama kimliği ~ işaretli)',
      'fields': [
        {
          'key': 'ADMOB_APP_ID_IOS',
          'label': 'iOS uygulama kimliği',
          'native': 'ios',
          'placeholder': 'ca-app-pub-…~…',
        },
        {
          'key': 'ADMOB_APP_ID_ANDROID',
          'label': 'Android uygulama kimliği',
          'native': 'android',
          'placeholder': 'ca-app-pub-…~…',
        },
      ],
    },
    {
      'id': 'backend',
      'title': 'Backend',
      'note': 'Uygulamanın konuştuğu API adresi (varsa).',
      'fields': [
        {
          'key': 'API_BASE_URL',
          'label': 'API taban adresi',
          'placeholder': 'https://api.sirketiniz.com',
        },
      ],
    },
    {
      'id': 'server',
      'title': 'Sunucu (site / backend yayını)',
      'note':
          'Panelin "Sunucuya kur" adımı bu bilgileri kullanır: SSH ile '
          'bağlanır, klasörü açar, depoyu çeker ve docker compose ile ayağa '
          'kaldırır. ANAHTAR tabanlı SSH gerekir — panel şifre soramaz '
          '(ssh-copy-id ile bir kez kurun).',
      'fields': [
        {
          'key': 'SERVER_HOST',
          'label': 'Sunucu adresi',
          'placeholder': '5.10.220.58',
          'desc': 'IP ya da alan adı.',
        },
        {
          'key': 'SERVER_USER',
          'label': 'SSH kullanıcısı',
          'placeholder': 'root',
          'desc': 'Boş bırakılırsa root kullanılır.',
        },
        {
          'key': 'SERVER_BASE_PATH',
          'label': 'Servis kök dizini',
          'placeholder': '/opt/services',
          'desc': 'Proje bunun altına <depo adı> klasörüyle kurulur.',
        },
      ],
    },
    {
      'id': 'signing_ios',
      'title': 'iOS imzalama — fastlane match (ileri düzey)',
      'note':
          'Sertifikaları makineler arası paylaşmak için. Boş bırakılırsa '
          'Xcode otomatik imzalaması kullanılır (yalnızca bu Mac\'te).',
      'help': 'https://docs.fastlane.tools/actions/match/',
      'helpLabel': 'fastlane match dokümanı',
      'fields': [
        {
          'key': 'MATCH_GIT_URL',
          'label': 'Sertifika deposu (private git)',
          'placeholder': 'git@github.com:kullanici/certs.git',
        },
        {'key': 'MATCH_PASSWORD', 'label': 'Sertifika şifresi', 'secret': true},
      ],
    },
  ];

  /// `.env`'i okur, şemayla birleştirir ve döndürür (GET) ya da gelen
  /// değerleri `.env`'e yazar (POST). Sır alanların değeri GET'te maskelenir.
  Future<Response> _config(Request request) async {
    final path = request.url.queryParameters['path'];
    if (path == null || path.isEmpty) {
      return _json({'error': 'path parametresi gerekli'}, status: 400);
    }
    if (!File(p.join(path, 'pubspec.yaml')).existsSync()) {
      return _json({'error': 'Proje bulunamadı: $path'}, status: 404);
    }
    final envPath = p.join(path, '.env');

    if (request.method == 'POST') {
      final body = await request.readAsString();
      final Map<String, dynamic> data = body.isEmpty
          ? {}
          : jsonDecode(body) as Map<String, dynamic>;
      final incoming = (data['values'] as Map?)?.cast<String, dynamic>() ?? {};
      // Yalnızca şemadaki anahtarları kabul et — .env'e keyfi satır girmesin.
      final allowed = _allKeys();
      final updates = <String, String>{}; // .env'e gidenler
      final nativeUpdates = <String, String>{}; // native dosyalara gidenler
      for (final entry in incoming.entries) {
        if (!allowed.contains(entry.key)) continue;
        // Satır sonu enjeksiyonunu kes.
        final val = entry.value
            .toString()
            .replaceAll(RegExp(r'[\r\n]'), ' ')
            .trim();
        if (_fieldSpec(entry.key)?['native'] != null) {
          nativeUpdates[entry.key] = val;
        } else {
          updates[entry.key] = val;
        }
      }
      // Hesap düzeyi SKALAR değerleri (Team ID, ASC Key/Issuer, match) her
      // kayıtta sessizce projenin .env'ine yaz — panelde göstermeden. Böylece
      // aynı bilgi iki yerde görünmez ama deploy için .env'de hazır olur.
      final account = _readAccount();
      for (final key in _accountKeys) {
        final spec = _fieldSpec(key);
        if (spec != null && spec['file'] == true) continue; // dosyalar ayrı
        final v = account[key] ?? '';
        if (v.isNotEmpty) updates[key] = v;
      }
      _writeEnv(envPath, updates);
      // Hesap düzeyi dosyalar (.p8 / Play JSON) projede yoksa ve hesap
      // varsayılanında varsa kopyala — böylece deploy tek Kaydet'le çalışır.
      _applyAccountFilesToProject(path);
      // AdMob uygulama kimliği .env'e değil native dosyalara yazılır.
      final warnings = _applyNativeAdmob(path, nativeUpdates);
      return _json({
        'ok': true,
        'saved': [...updates.keys, ...nativeUpdates.keys],
        if (warnings.isNotEmpty) 'warnings': warnings,
      });
    }

    // GET — HESAP düzeyi alanlar burada GÖSTERİLMEZ; onlar "Hesap
    // Varsayılanları"nda yönetilir ve kayıtta sessizce .env'e yazılır. Burada
    // yalnızca uygulamaya özel alanlar döner.
    final existing = _readEnv(envPath);
    final groups = <Map<String, dynamic>>[];
    for (final g in _configGroups) {
      final fields = <Map<String, dynamic>>[];
      for (final f in (g['fields'] as List).cast<Map<String, dynamic>>()) {
        final key = f['key'] as String;
        if (_accountKeys.contains(key)) continue; // Hesap Varsayılanları'nda
        final native = f['native'] as String?;
        if (native != null) {
          // Değer .env'de değil native dosyada (Info.plist / Manifest).
          final v = _readNativeAdmob(path, native);
          if (v == null) continue; // dosyada anahtar yok → alanı gösterme
          fields.add({
            ...f,
            'value': v,
            'set': v.isNotEmpty,
            // Google'ın test yayıncı kimliği: çalışır ama gelir sıfır.
            'test': v.contains('ca-app-pub-3940256099942544'),
          });
          continue;
        }
        final raw = existing[key] ?? '';
        final isSecret = f['secret'] == true;
        final isFile = f['file'] == true;
        // Reklam BİRİMİ kimliği: boş ya da test yayıncısı → test reklamı,
        // gelir sıfır. Kullanıcı hangi birimlerin geliri sıfır gördüğünü
        // tek bakışta anlasın.
        final isAdUnit = g['id'] == 'admob';
        fields.add({
          ...f,
          'value': (isSecret || isFile) ? '' : raw,
          'set': raw.isNotEmpty,
          if (isFile && raw.isNotEmpty) 'fileName': p.basename(raw),
          if (isAdUnit)
            'test': raw.isEmpty || raw.contains('ca-app-pub-3940256099942544'),
        });
      }
      // Bütün alanları elenen grubu (ör. reklam yoksa app id) hiç gösterme.
      if (fields.isNotEmpty) groups.add({...g, 'fields': fields});
    }
    return _json({
      'root': path,
      'envExists': File(envPath).existsSync(),
      'groups': groups,
    });
  }

  /// Yüklenen anahtar dosyasını (.p8 / .json) projedeki hedef klasöre yazar ve
  /// `.env`'deki ilgili yolu günceller. Dosya içeriği ham gövde olarak gelir;
  /// çok parçalı ayrıştırmaya gerek kalmaz.
  Future<Response> _configUpload(Request request) async {
    final q = request.url.queryParameters;
    final path = q['path'];
    final field = q['field'];
    final fileName = q['filename'];
    if (path == null || field == null || fileName == null) {
      return _json({'error': 'path, field ve filename gerekli'}, status: 400);
    }
    // Alanı şemadan bul (hedef klasör ve dosya olup olmadığı oradan gelir).
    final spec = _fieldSpec(field);
    if (spec == null || spec['file'] != true) {
      return _json({'error': 'Dosya alanı değil: $field'}, status: 400);
    }
    // Dosya adını güvenli hale getir — dizin geçişi olmasın.
    final safeName = p.basename(fileName);
    final destDir = spec['dest'] as String;
    final relPath = './$destDir/$safeName';
    final absDir = Directory(p.join(path, destDir));
    absDir.createSync(recursive: true);
    final bytes = await request.read().expand((c) => c).toList();
    File(p.join(absDir.path, safeName)).writeAsBytesSync(bytes);
    // .env'deki yolu ayarla.
    _writeEnv(p.join(path, '.env'), {field: relPath});
    return _json({
      'ok': true,
      'field': field,
      'path': relPath,
      'fileName': safeName,
    });
  }

  /// Native dosyadaki (Info.plist / AndroidManifest) mevcut AdMob uygulama
  /// kimliği; dosya ya da anahtar yoksa `null`.
  String? _readNativeAdmob(String path, String platform) {
    final file = platform == 'ios'
        ? File(p.join(path, 'ios/Runner/Info.plist'))
        : File(p.join(path, 'android/app/src/main/AndroidManifest.xml'));
    if (!file.existsSync()) return null;
    final content = file.readAsStringSync();
    return platform == 'ios'
        ? readAdmobAppIdIos(content)
        : readAdmobAppIdAndroid(content);
  }

  /// AdMob uygulama kimliğini native dosyalara yazar. Boş değerler atlanır.
  /// Uygulanamayan yamaların açıklamasını (uyarı) döndürür.
  List<String> _applyNativeAdmob(String path, Map<String, String> updates) {
    final warnings = <String>[];
    updates.forEach((key, value) {
      if (value.isEmpty) return;
      final platform = _fieldSpec(key)?['native'] as String?;
      final file = platform == 'ios'
          ? File(p.join(path, 'ios/Runner/Info.plist'))
          : File(p.join(path, 'android/app/src/main/AndroidManifest.xml'));
      if (!file.existsSync()) {
        warnings.add('${file.path} bulunamadı.');
        return;
      }
      final result = platform == 'ios'
          ? setAdmobAppIdIos(file.readAsStringSync(), value)
          : setAdmobAppIdAndroid(file.readAsStringSync(), value);
      if (!result.ok) {
        warnings.add('$platform: ${result.problem}');
        return;
      }
      file.writeAsStringSync(result.content);
    });
    return warnings;
  }

  Set<String> _allKeys() => {
    for (final g in _configGroups)
      for (final f in (g['fields'] as List).cast<Map<String, dynamic>>())
        f['key'] as String,
  };

  Map<String, dynamic>? _fieldSpec(String key) {
    for (final g in _configGroups) {
      for (final f in (g['fields'] as List).cast<Map<String, dynamic>>()) {
        if (f['key'] == key) return f;
      }
    }
    return null;
  }

  /// `.env`'i KEY=VALUE haritası olarak okur (tırnakları soyar). Yorumları ve
  /// bilinmeyen satırları görmezden gelir.
  Map<String, String> _readEnv(String envPath) {
    final file = File(envPath);
    if (!file.existsSync()) return {};
    final map = <String, String>{};
    for (final line in file.readAsLinesSync()) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      final eq = trimmed.indexOf('=');
      if (eq <= 0) continue;
      final key = trimmed.substring(0, eq).trim();
      var value = trimmed.substring(eq + 1).trim();
      if (value.length >= 2 &&
          ((value.startsWith('"') && value.endsWith('"')) ||
              (value.startsWith("'") && value.endsWith("'")))) {
        value = value.substring(1, value.length - 1);
      }
      map[key] = value;
    }
    return map;
  }

  /// Verilen anahtarları `.env`'e yazar: var olan satırı değiştirir, yoksa
  /// ekler; dosyadaki diğer satırları ve yorumları KORUR. Boş değer verilen
  /// anahtarın satırı silinir (temiz kalsın diye).
  void _writeEnv(String envPath, Map<String, String> updates) {
    final file = File(envPath);
    final lines = file.existsSync() ? file.readAsLinesSync() : <String>[];
    final remaining = Map<String, String>.from(updates);
    final out = <String>[];

    String format(String key, String value) {
      // Boşluk, # veya tırnak içeren değeri çift tırnakla sar.
      final needsQuote =
          value.contains(' ') ||
          value.contains('#') ||
          value.contains('"') ||
          value.contains("'");
      final safe = value.replaceAll('"', r'\"');
      return needsQuote ? '$key="$safe"' : '$key=$value';
    }

    for (final line in lines) {
      final trimmed = line.trim();
      final eq = trimmed.indexOf('=');
      if (trimmed.isEmpty || trimmed.startsWith('#') || eq <= 0) {
        out.add(line);
        continue;
      }
      final key = trimmed.substring(0, eq).trim();
      if (remaining.containsKey(key)) {
        final value = remaining.remove(key)!;
        if (value.isEmpty) continue; // boşsa satırı düşür
        out.add(format(key, value));
      } else {
        out.add(line);
      }
    }
    // Dosyada hiç olmayan yeni anahtarları sona ekle.
    final added = remaining.entries.where((e) => e.value.isNotEmpty).toList();
    if (added.isNotEmpty) {
      if (out.isNotEmpty && out.last.trim().isNotEmpty) out.add('');
      out.add('# forge panelinden eklendi');
      for (final e in added) {
        out.add(format(e.key, e.value));
      }
    }
    file.writeAsStringSync('${out.join('\n')}\n');
  }

  // ------------------------------------------------------- hesap varsayılanları

  /// Hesap düzeyi varsayılanların saklandığı dizin: ~/.forge (depo dışında,
  /// makineye özel). Aynı Apple/Play hesabını kullanan tüm uygulamalar buradan
  /// beslenir.
  String get _accountDir {
    final home =
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.current.path;
    return p.join(home, '.forge');
  }

  String get _accountJson => p.join(_accountDir, 'account.json');

  Map<String, String> _readAccount() {
    final f = File(_accountJson);
    if (!f.existsSync()) return {};
    try {
      final m = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      return m.map((k, v) => MapEntry(k, v.toString()));
    } catch (_) {
      return {};
    }
  }

  void _writeAccount(Map<String, String> updates) {
    Directory(_accountDir).createSync(recursive: true);
    final current = _readAccount();
    for (final e in updates.entries) {
      if (e.value.isEmpty) {
        current.remove(e.key);
      } else {
        current[e.key] = e.value;
      }
    }
    File(
      _accountJson,
    ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(current));
  }

  /// GET: yalnızca hesap düzeyi alanları döndürür. POST: onları ~/.forge'a yazar.
  Future<Response> _account(Request request) async {
    if (request.method == 'POST') {
      final body = await request.readAsString();
      final Map<String, dynamic> data = body.isEmpty
          ? {}
          : jsonDecode(body) as Map<String, dynamic>;
      final incoming = (data['values'] as Map?)?.cast<String, dynamic>() ?? {};
      final updates = <String, String>{};
      for (final e in incoming.entries) {
        if (!_accountKeys.contains(e.key)) continue;
        updates[e.key] = e.value
            .toString()
            .replaceAll(RegExp(r'[\r\n]'), ' ')
            .trim();
      }
      _writeAccount(updates);
      return _json({'ok': true, 'saved': updates.keys.toList()});
    }

    final saved = _readAccount();
    final groups = <Map<String, dynamic>>[];
    for (final g in _configGroups) {
      final fields = <Map<String, dynamic>>[];
      for (final f in (g['fields'] as List).cast<Map<String, dynamic>>()) {
        final key = f['key'] as String;
        if (!_accountKeys.contains(key)) continue;
        final raw = saved[key] ?? '';
        final isSecret = f['secret'] == true;
        final isFile = f['file'] == true;
        fields.add({
          ...f,
          'value': (isSecret || isFile) ? '' : raw,
          'set': raw.isNotEmpty,
          if (isFile && raw.isNotEmpty) 'fileName': p.basename(raw),
        });
      }
      if (fields.isNotEmpty) groups.add({...g, 'fields': fields});
    }
    return _json({'groups': groups});
  }

  /// Hesap düzeyi dosyayı (.p8 / Play JSON) ~/.forge'a yazar ve yolu kaydeder.
  Future<Response> _accountUpload(Request request) async {
    final q = request.url.queryParameters;
    final field = q['field'];
    final fileName = q['filename'];
    if (field == null || fileName == null) {
      return _json({'error': 'field ve filename gerekli'}, status: 400);
    }
    final spec = _fieldSpec(field);
    if (spec == null || spec['file'] != true || !_accountKeys.contains(field)) {
      return _json({'error': 'Hesap dosya alanı değil: $field'}, status: 400);
    }
    final safeName = p.basename(fileName);
    Directory(_accountDir).createSync(recursive: true);
    final abs = p.join(_accountDir, safeName);
    final bytes = await request.read().expand((c) => c).toList();
    File(abs).writeAsBytesSync(bytes);
    _writeAccount({field: abs});
    return _json({'ok': true, 'field': field, 'fileName': safeName});
  }

  /// Hesap düzeyi dosyaları, projede henüz yoksa projeye kopyalar ve `.env`
  /// yolunu ayarlar. Config kaydında çağrılır.
  void _applyAccountFilesToProject(String path) {
    final account = _readAccount();
    final projectEnv = _readEnv(p.join(path, '.env'));
    for (final key in _accountKeys) {
      final spec = _fieldSpec(key);
      if (spec == null || spec['file'] != true) continue;
      final accFile = account[key] ?? '';
      if (accFile.isEmpty) continue;
      if ((projectEnv[key] ?? '').isNotEmpty) continue; // proje zaten dolu
      final src = File(accFile);
      if (!src.existsSync()) continue;
      final destDir = spec['dest'] as String;
      final name = p.basename(accFile);
      final absDir = Directory(p.join(path, destDir))
        ..createSync(recursive: true);
      src.copySync(p.join(absDir.path, name));
      _writeEnv(p.join(path, '.env'), {key: './$destDir/$name'});
    }
  }

  // -------------------------------------------------- sunucuya kurulum

  /// Projeyi sunucuya kurar: klasörü açar, depoyu çeker (yoksa klonlar) ve
  /// docker compose ile ayağa kaldırır — hepsi tek SSH oturumunda.
  ///
  /// Sunucu kodu GIT'TEN alır, bu makineden değil. Bu yüzden commit'lenmemiş
  /// ya da push'lanmamış iş varsa BAŞLAMAZ: yoksa "panelden kurdum ama
  /// değişikliğim yok" tuzağı doğar ve sebebi hiç görünmez.
  /// "Sunucuya kur" ve "Sunucuyu güncelle" için ortak ön kontroller ve
  /// hedef bilgisi. Hata varsa [_ServerTarget.error] dolu döner ve çağıran
  /// onu olduğu gibi yanıtlar.
  ///
  /// İki düğme de kodu git'ten çektiği için aynı şartları ister: temiz
  /// çalışma ağacı, push'lanmış dal, compose dosyası ve sabit proje adı.
  _ServerTarget _serverTarget(Request request) {
    final path = request.url.queryParameters['path'];
    if (path == null || path.isEmpty) {
      return _ServerTarget.fail(_sseError('path parametresi gerekli'));
    }

    final account = _readAccount();
    String setting(String key, String fallback) {
      final v = (account[key] ?? '').trim();
      return v.isEmpty ? fallback : v;
    }

    final host = setting('SERVER_HOST', '');
    if (host.isEmpty) {
      return _ServerTarget.fail(
        _sseError(
          'Sunucu adresi tanımlı değil. Soldaki ⚙ Hesap Varsayılanları → '
          '"Sunucu" bölümünü doldurun.',
        ),
      );
    }
    final user = setting('SERVER_USER', 'root');
    final base = setting('SERVER_BASE_PATH', '/opt/services');

    // Depo kökü: Flutter projesi app/ altında olabilir, git kökü üsttedir.
    final repoRoot = _gitOutput(path, ['rev-parse', '--show-toplevel']);
    if (repoRoot == null) {
      return _ServerTarget.fail(_sseError('Git deposu bulunamadı: $path'));
    }
    final remoteUrl = _gitOutput(repoRoot, ['remote', 'get-url', 'origin']);
    if (remoteUrl == null || remoteUrl.isEmpty) {
      return _ServerTarget.fail(
        _sseError(
          'Deponun "origin" uzak adresi yok. Sunucu kodu git\'ten çeker; '
          'önce depoyu GitHub\'a bağlayın.',
        ),
      );
    }

    // --- yerel iş bitmiş mi? (sunucu git'ten çekeceği için şart)
    final dirty = _gitOutput(repoRoot, ['status', '--porcelain']);
    if (dirty != null && dirty.isNotEmpty) {
      return _ServerTarget.fail(
        _sseError(
          'Yerelde commit\'lenmemiş değişiklikler var. Sunucu git\'ten '
          'çektiği için bunlar kurulmaz — önce commit\'leyip push edin.',
        ),
      );
    }
    final branch = _gitOutput(repoRoot, ['rev-parse', '--abbrev-ref', 'HEAD']);
    if (branch == null || branch.isEmpty || branch == 'HEAD') {
      return _ServerTarget.fail(
        _sseError('Geçerli bir dal bulunamadı (detached HEAD?).'),
      );
    }
    final unpushed = _gitOutput(repoRoot, ['log', '--oneline', '@{u}..HEAD']);
    if (unpushed == null) {
      return _ServerTarget.fail(
        _sseError(
          '"$branch" dalının uzak karşılığı yok. Önce gönderin:\n'
          '  git push -u origin $branch',
        ),
      );
    }
    if (unpushed.isNotEmpty) {
      final count = unpushed.split('\n').where((l) => l.isNotEmpty).length;
      return _ServerTarget.fail(
        _sseError(
          'Gönderilmemiş $count commit var — sunucu bunları göremez. Önce:\n'
          '  git push\n\n$unpushed',
        ),
      );
    }

    // --- hangi klasörde compose var?
    const candidates = ['site', 'backend', '.'];
    String? composeDir;
    for (final dir in candidates) {
      if (File(p.join(repoRoot, dir, 'docker-compose.yml')).existsSync()) {
        composeDir = dir;
        break;
      }
    }
    if (composeDir == null) {
      return _ServerTarget.fail(
        _sseError(
          'docker-compose.yml bulunamadı (bakılan yerler: '
          '${candidates.join(", ")}). Sunucuya kurulacak bir servis yok.',
        ),
      );
    }

    final composeText = File(
      p.join(repoRoot, composeDir, 'docker-compose.yml'),
    ).readAsStringSync();

    // --- compose proje adı sabit mi?
    //
    // Verilmezse ad çalışma dizininden türetilir ve aynı sunucudaki her
    // "backend/" klasörü AYNI proje sayılır: ikinci yığın ilkinin
    // konteynerlerini siler, veritabanını devralır ve "<dizin>-api" imajının
    // üzerine yazar. Gerçekten başımıza geldi (jumptoup kurulunca Vaktinde
    // çevrimdışı kaldı), bu yüzden kurulum burada durur.
    final projectName = composeProjectName(composeText);
    if (projectName == null) {
      return _ServerTarget.fail(
        _sseError(
          '$composeDir/docker-compose.yml proje adı tanımlamıyor.\n\n'
          'Ad verilmezse Docker onu klasör adından ("$composeDir") türetir ve '
          'aynı sunucudaki başka bir yığın da aynı adı kullanıyorsa onun '
          'konteynerlerini siler, veritabanını devralır. Dosyanın en üstüne '
          'ekleyin:\n\n'
          '  name: ${p.basename(repoRoot)}',
        ),
      );
    }

    final name = p.basename(repoRoot);
    return _ServerTarget(
      repoRoot: repoRoot,
      host: host,
      user: user,
      base: base,
      target: p.posix.join(base, name),
      cloneUrl: _sunucuGitAdresi(remoteUrl),
      branch: branch,
      composeDir: composeDir,
      projectName: projectName,
    );
  }

  /// Kurulumdan/güncellemeden sonra durumu doğrulayan ortak betik parçası:
  /// "başladı" ile "çalışıyor" aynı şey değil; restart döngüsü sessizce
  /// başarılı görünüyordu.
  static const _saglikKontrolu = '''
echo "→ durum bekleniyor (20 sn)…"
sleep 20
echo "→ durum:"
docker compose ps
if docker compose ps --format '{{.Name}} {{.State}}' 2>/dev/null | grep -qi restart; then
  echo ""
  echo "✋ UYARI: bir konteyner restart döngüsünde. Son loglar:"
  docker compose logs --tail 25
  exit 1
fi
''';

  Response _sshRun(_ServerTarget t, String script) {
    return _spawn('ssh', [
      // BatchMode: anahtar yoksa şifre beklemek yerine hemen ve anlaşılır
      // biçimde başarısız olur — panel etkileşimli soru soramaz.
      '-o', 'BatchMode=yes',
      '-o', 'StrictHostKeyChecking=accept-new',
      '${t.user}@${t.host}',
      script,
    ], workingDir: t.repoRoot);
  }

  /// "Sunucuyu güncelle": var olan kurulumu git'ten çeker ve konteynerleri
  /// yeniden kurar. İlk kurulumun aksine .env üretmez, port bakmaz — o
  /// adımlar bir kez yapılır; burada yalnızca kod değişir.
  ///
  /// `docker compose up -d --build` bilinçli: kod imaja COPY ile giriyor,
  /// dolayısıyla "restart" tek başına eski kodu yeniden başlatırdı.
  /// Değişmeyen imaj katmanları önbellekten gelir, yani bu hızlıdır.
  Response _serverUpdate(Request request) {
    final t = _serverTarget(request);
    final error = t.error;
    if (error != null) return error;

    final script =
        '''
set -e
if [ ! -d ${_shq('${t.target}/.git')} ]; then
  echo "✋ DURDU: sunucuda kurulum yok: ${_shq(t.target)}"
  echo "   Önce "Sunucuya kur" düğmesini kullanın."
  exit 1
fi
cd ${_shq(t.target)}
eski=\$(git rev-parse --short HEAD)
echo "→ sunucudaki sürüm: \$eski (\$(git log -1 --pretty=%s))"
echo "→ git fetch + pull (${_shq(t.branch)})"
git fetch --prune origin
git checkout ${_shq(t.branch)}
git pull --ff-only
yeni=\$(git rev-parse --short HEAD)
if [ "\$eski" = "\$yeni" ]; then
  echo "→ yeni commit yok; konteynerler yine de yeniden kuruluyor"
else
  echo "→ yeni sürüm: \$yeni (\$(git log -1 --pretty=%s))"
  echo "→ gelen commit'ler:"
  git log --oneline "\$eski..\$yeni" | sed 's/^/     /'
fi
cd ${_shq(t.composeDir)}
if [ ! -f .env ]; then
  echo "✋ DURDU: ${_shq(t.composeDir)}/.env yok. Bu bir ilk kurulum; "Sunucuya kur" kullanın."
  exit 1
fi
echo "→ docker compose up -d --build  (${_shq(t.composeDir)})"
docker compose up -d --build
$_saglikKontrolu
echo "✅ güncelleme tamam — \$yeni çalışıyor"
port=\$(grep -E '^API_PORT=' .env 2>/dev/null | cut -d= -f2 | tr -d ' ' || true)
echo "   yerel doğrulama:  curl 127.0.0.1:\${port:-8000}/health"
''';

    return _sshRun(t, script);
  }

  Response _serverDeploy(Request request) {
    final t = _serverTarget(request);
    final error = t.error;
    if (error != null) return error;
    final target = t.target;
    final base = t.base;
    final branch = t.branch;
    final cloneUrl = t.cloneUrl;
    final composeDir = t.composeDir;
    final projectName = t.projectName;

    // Uzak kabukta çalışacak betik. Değerler tek tırnakla kaçırılır:
    // kullanıcının girdiği yol/ad uzak kabukta komuta dönüşemez.
    //
    // Betik dört emniyet adımı içerir; hepsi sunucuda gerçekten yaşanmış
    // hatalardan doğdu:
    //   1. Proje adı sunucuda BAŞKA bir compose dosyasına bağlıysa dur —
    //      devralmak, o yığının konteynerlerini silmek demek.
    //   2. Port başka bir servis tarafından dinleniyorsa dur.
    //   3. .env yoksa üret, VARSA dokunma — parolayı yeniden üretmek
    //      veritabanını kilitler.
    //   4. Kurulumdan sonra durumu doğrula: "başladı" ile "çalışıyor" aynı
    //      şey değil; restart döngüsü sessizce başarılı görünüyordu.
    final script =
        '''
set -e
echo "→ hedef: ${_shq(target)}"
mkdir -p ${_shq(base)}
if [ -d ${_shq('$target/.git')} ]; then
  echo "→ var olan kopya güncelleniyor (git pull)"
  cd ${_shq(target)}
  git fetch --prune origin
  git checkout ${_shq(branch)}
  git pull --ff-only
else
  echo "→ depo klonlanıyor: ${_shq(cloneUrl)}"
  git clone --branch ${_shq(branch)} ${_shq(cloneUrl)} ${_shq(target)}
  cd ${_shq(target)}
fi
echo "→ sürüm: \$(git rev-parse --short HEAD) (\$(git log -1 --pretty=%s))"
cd ${_shq(composeDir)}

# 1) proje adı başka bir yığına mı ait?
# "docker compose ls -a" son sütunda projenin config dosyalarını verir.
mevcut=\$(docker compose ls -a 2>/dev/null \\
  | awk -v ad=${_shq(projectName)} '\$1 == ad { print \$NF }' | head -1)
beklenen=${_shq('$target/$composeDir/docker-compose.yml')}
if [ -n "\$mevcut" ] && [ "\$mevcut" != "\$beklenen" ]; then
  echo "✋ DURDU: ${_shq(projectName)} adlı compose projesi bu sunucuda"
  echo "   BAŞKA bir dosyaya bağlı:"
  echo "     \$mevcut"
  echo "   beklenen:"
  echo "     \$beklenen"
  echo "   Devam etmek o yığının konteynerlerini silerdi. compose dosyasındaki"
  echo "   name: alanını benzersiz yapın ya da eski yığını önce kaldırın."
  exit 1
fi

# 2) .env yoksa üret, varsa dokunma
if [ ! -f .env ] && [ -f .env.example ]; then
  echo "→ .env yok, .env.example'dan üretiliyor (parola bir kez atanır)"
  cp .env.example .env
  if grep -q '^POSTGRES_PASSWORD=\$' .env; then
    sifre=\$(openssl rand -base64 24 | tr -d '\\n/')
    sed -i "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=\$sifre|" .env
  fi
elif [ -f .env ]; then
  echo "→ .env yerinde, dokunulmuyor"
fi

# 3) port başkası tarafından dinleniyor mu?
port=\$(grep -E '^API_PORT=' .env 2>/dev/null | cut -d= -f2 | tr -d ' ' || true)
port=\${port:-8000}
if command -v ss >/dev/null 2>&1; then
  kendi=\$(docker compose ps -q 2>/dev/null | wc -l)
  if [ "\$kendi" = "0" ] && ss -ltn "sport = :\$port" 2>/dev/null | grep -q LISTEN; then
    echo "✋ DURDU: \$port portu başka bir servis tarafından dinleniyor."
    echo "   .env içindeki API_PORT değerini boş bir portla değiştirin."
    exit 1
  fi
fi

echo "→ docker compose up -d --build  (${_shq(composeDir)})"
docker compose up -d --build

# 4) gerçekten çalışıyor mu? (başladı ≠ çalışıyor)
$_saglikKontrolu
echo "✅ kurulum tamam — konteynerler ayakta"
echo "   yerel doğrulama:  curl 127.0.0.1:\$port/health"
''';

    return _sshRun(t, script);
  }

  /// Git komutunu çalıştırır ve çıktısını döndürür; komut başarısızsa `null`.
  String? _gitOutput(String dir, List<String> args) {
    try {
      final r = Process.runSync('git', args, workingDirectory: dir);
      if (r.exitCode != 0) return null;
      return r.stdout.toString().trim();
    } catch (_) {
      return null;
    }
  }

  /// Değeri uzak kabuk için tek tırnakla kaçırır.
  static String _shq(String value) => "'${value.replaceAll("'", r"'\''")}'";

  /// Sunucunun klonlarken kullanacağı adres.
  ///
  /// HTTPS adresleri SSH biçimine çevrilir: sunucu depoya anahtarla
  /// (deploy key) erişir, HTTPS ise başsız makinede jeton gömmeyi
  /// gerektirir ve private depoda sessizce kimlik doğrulama hatası verir.
  /// Yalnızca İLK klonlamayı etkiler; sonraki güncellemeler sunucudaki
  /// remote'u kullanır. Sunucunuz HTTPS+jeton kullanıyorsa ilk klonlamayı
  /// elle yapın, panel sonrasını yürütür.
  static String _sunucuGitAdresi(String url) {
    final m = RegExp(r'^https://([^/@]+)/(.+?)(?:\.git)?/?$').firstMatch(url);
    if (m == null) return url; // zaten SSH ya da tanımadığımız biçim
    return 'git@${m.group(1)}:${m.group(2)}.git';
  }

  // ------------------------------------------------------------ deploy

  Response _deploy(Request request) {
    final q = request.url.queryParameters;
    final path = q['path'];
    final platform = q['platform'];
    final lane = q['lane'];
    if (path == null || platform == null || lane == null) {
      return _sseError('path, platform ve lane parametreleri gerekli');
    }
    if (!['ios', 'android', 'all'].contains(platform)) {
      return _sseError('platform ios | android | all olmalı');
    }
    if (!['beta', 'release'].contains(lane)) {
      return _sseError('lane beta | release olmalı');
    }

    final dryRun = q['dryrun'] != '0'; // varsayılan: deneme çalıştırması
    // GERÇEK yükleme geri alınamaz ve dışa dönüktür. Bilinçli, ayrı bir
    // onay olmadan asla başlatılmaz — panelin düğmesine basmak insanın
    // işidir, panelin değil.
    if (!dryRun && q['confirm'] != 'YAYINLA') {
      return _sseError(
        'Gerçek yükleme için onay gerekli. Bu geri alınamaz bir işlemdir; '
        'panelde onay kutusunu doldurun.',
      );
    }

    final deployScript = File(p.join(path, 'deploy.sh'));
    if (!deployScript.existsSync()) {
      return _sseError('deploy.sh bulunamadı: ${deployScript.path}');
    }

    // Sürüm notu (testçilere/mağazaya gösterilir). Tek argüman olarak geçer,
    // kabuk araya girmez — kullanıcı metni güvenle taşınır.
    final notes = q['notes'];

    final args = [
      'deploy.sh',
      platform,
      lane,
      if (dryRun) '--dry-run',
      if (notes != null && notes.trim().isNotEmpty) '--notes=${notes.trim()}',
    ];
    return _spawn('bash', args, workingDir: path);
  }

  // ----------------------------------------------------- süreç akıtma

  /// Tek bir süreci başlatır — çok adımlı [_run] için ince sarmalayıcı.
  Response _spawn(
    String executable,
    List<String> args, {
    required String workingDir,
  }) {
    return _run([_Step(executable, args, workingDir)]);
  }

  /// Verilen adımları SIRAYLA çalıştırır ve stdout+stderr'ini satır satır SSE
  /// olarak akıtır. Bir adım başarısız olursa (çıkış kodu ≠ 0) zincir orada
  /// durur — örneğin `forge new` çökerse ardından `gh repo create` çalışmaz.
  ///
  /// Argümanlar bilinçli olarak dizi geçer, kabuğa değil: kullanıcının girdiği
  /// ad/açıklama gibi değerlerin `bash -c` içinde komut enjeksiyonuna dönüşmesi
  /// böyle imkânsız olur. Aynı anda yalnızca bir değiştiren iş çalışabilir.
  Response _run(List<_Step> steps) {
    if (_busy) {
      return _sseError(
        'Şu anda başka bir işlem çalışıyor. Bitmesini bekleyin.',
      );
    }
    _busy = true;

    final controller = StreamController<List<int>>();

    void send(String event, Object data) {
      if (controller.isClosed) return;
      controller.add(
        utf8.encode(
          'event: $event\n'
          'data: ${jsonEncode(data)}\n\n',
        ),
      );
    }

    Future<int> runStep(_Step step) async {
      final process = await Process.start(
        step.executable,
        step.args,
        workingDirectory: step.workingDir,
        // Çıktı karışsın ki sıra korunsun (fastlane hem stdout hem stderr
        // kullanıyor). Yerel eksikse çocuk sürece UTF-8 enjekte edilir:
        // CocoaPods/fastlane bunsuz çöker ve sunucunun nereden
        // başlatıldığına bağlı olmamalı.
        //
        // PWD açıkça verilir: launchd altında panele "PWD=." gibi bozuk bir
        // değer miras kalabiliyor; bash bunu geçerli sayıp "$PWD/..." ile
        // kurulan yolları görünmez biçimde göreli bırakıyor (deploy.sh'ın
        // .p8 yolu böyle kırılmıştı).
        environment: {..._localeFix, 'PWD': step.workingDir},
        mode: ProcessStartMode.normal,
      );

      final lines = StreamController<String>();
      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(lines.add);
      process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(lines.add);

      final sub = lines.stream.listen((line) => send('line', {'text': line}));
      final code = await process.exitCode;
      await sub.cancel();
      await lines.close();
      return code;
    }

    Future<void> pump() async {
      final multi = steps.length > 1;
      var code = 0;
      try {
        for (var i = 0; i < steps.length; i++) {
          final step = steps[i];
          final cmd = '${step.executable} ${step.args.join(' ')}';
          if (i == 0) {
            send('start', {'cmd': cmd, 'cwd': step.workingDir});
          } else {
            // Adım başlığını konsola göze çarpan bir satır olarak yaz.
            send('line', {'text': ''});
            send('line', {
              'text':
                  '── adım ${i + 1}/${steps.length}'
                  '${step.label != null ? ': ${step.label}' : ''} ──',
            });
            send('line', {'text': '\$ $cmd'});
          }
          code = await runStep(step);
          if (code != 0) {
            if (multi && i < steps.length - 1) {
              send('line', {
                'text': '❌ Adım başarısız (kod $code) — zincir durduruldu.',
              });
            }
            break;
          }
        }
        send('done', {'code': code, 'ok': code == 0});
      } catch (e) {
        send('line', {'text': '❌ Başlatılamadı: $e'});
        send('done', {'code': -1, 'ok': false});
      } finally {
        _busy = false;
        await controller.close();
      }
    }

    // İstemci bağlantıyı keserse süreci öksüz bırakmamak için akışı kapat.
    controller.onCancel = () {
      _busy = false;
    };
    unawaited(pump());

    return Response.ok(
      controller.stream,
      headers: {
        'Content-Type': 'text/event-stream',
        'Cache-Control': 'no-cache',
        'Connection': 'keep-alive',
      },
      context: {'shelf.io.buffer_output': false},
    );
  }

  Response _sseError(String message) {
    final body =
        'event: line\ndata: ${jsonEncode({'text': '❌ $message'})}\n\n'
        'event: done\ndata: ${jsonEncode({'code': -1, 'ok': false})}\n\n';
    return Response.ok(
      body,
      headers: {
        'Content-Type': 'text/event-stream',
        'Cache-Control': 'no-cache',
      },
    );
  }

  // ----------------------------------------------------- statik dosyalar

  Response _static(String path) {
    final rel = path.isEmpty ? 'index.html' : path;
    final file = File(p.join(_webDir, rel));
    // Dizin dışına çıkma denemelerini engelle.
    if (!p.isWithin(_webDir, file.path) &&
        p.normalize(file.path) != p.join(_webDir, 'index.html')) {
      if (!p.equals(file.parent.path, _webDir) &&
          !p.isWithin(_webDir, file.path)) {
        return Response.notFound('yok');
      }
    }
    if (!file.existsSync()) return Response.notFound('yok');
    return Response.ok(
      file.readAsBytesSync(),
      headers: {
        'Content-Type': _contentType(rel),
        // Panel yerel bir geliştirme aracı: tarayıcının bayat JS/CSS
        // önbelleği "eski kod çalışıyor" karışıklığına yol açıyor.
        'Cache-Control': 'no-store',
      },
    );
  }

  String _contentType(String path) {
    if (path.endsWith('.html')) return 'text/html; charset=utf-8';
    if (path.endsWith('.css')) return 'text/css; charset=utf-8';
    if (path.endsWith('.js')) return 'text/javascript; charset=utf-8';
    if (path.endsWith('.svg')) return 'image/svg+xml';
    if (path.endsWith('.json')) return 'application/json; charset=utf-8';
    return 'text/plain; charset=utf-8';
  }

  Response _json(Object data, {int status = 200}) => Response(
    status,
    body: jsonEncode(data),
    headers: {'Content-Type': 'application/json; charset=utf-8'},
  );
}

/// [_run] için tek bir komut adımı. Argümanlar dizidir; kabuk araya girmez.
class _Step {
  _Step(this.executable, this.args, this.workingDir, {this.label});
  final String executable;
  final List<String> args;
  final String workingDir;

  /// Konsolda adım başlığı olarak gösterilecek kısa etiket (çok adımlı işler).
  final String? label;
}

/// forge deposunun kökünü bulur (pubspec.yaml → name: forge).
///
/// Panel deponun içinden çalıştırıldığı varsayımına GÜVENMEZ: betiğin
/// bulunduğu yerden yukarı doğru arar.
String resolveForgeRoot() {
  var dir = Directory(p.dirname(Platform.script.toFilePath()));
  for (var i = 0; i < 6; i++) {
    final pubspec = File(p.join(dir.path, 'pubspec.yaml'));
    if (pubspec.existsSync() &&
        pubspec.readAsStringSync().contains('name: forge')) {
      return dir.path;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  // Son çare: çalışma dizini.
  return Directory.current.path;
}

/// Sunucu düğmelerinin ön kontrolden geçmiş hedefi. [error] doluysa diğer
/// alanlar anlamsızdır; çağıran yanıtı olduğu gibi döndürür.
class _ServerTarget {
  _ServerTarget({
    required this.repoRoot,
    required this.host,
    required this.user,
    required this.base,
    required this.target,
    required this.cloneUrl,
    required this.branch,
    required this.composeDir,
    required this.projectName,
  }) : error = null;

  _ServerTarget.fail(this.error)
      : repoRoot = '',
        host = '',
        user = '',
        base = '',
        target = '',
        cloneUrl = '',
        branch = '',
        composeDir = '',
        projectName = '';

  final Response? error;
  final String repoRoot;
  final String host;
  final String user;
  final String base;
  final String target;
  final String cloneUrl;
  final String branch;
  final String composeDir;
  final String projectName;
}
