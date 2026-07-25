/// `flutter create` çıktısını standarda getiren yamalar.
///
/// Hepsi saf metin fonksiyonudur: girdi dosya içeriği, çıktı yeni içerik.
/// Dosya sistemine dokunmazlar, bu yüzden gerçek bir Xcode projesi
/// kurmadan test edilebilirler — bu dosyadaki hataların bedeli yüksek
/// olduğu için önemli.
///
/// Ortak sözleşme: yama zaten uygulanmışsa içerik AYNEN döner. Böylece
/// komutlar tekrar çalıştırılabilir.
library;

/// Yama uygulanamadığında sebebi taşır.
class PatchResult {
  const PatchResult(this.content, {this.problem});

  final String content;

  /// `null` değilse yama uygulanamadı; kullanıcıya söylenmelidir.
  final String? problem;

  bool get ok => problem == null;
}

// --------------------------------------------------------------- Info.plist

/// Standart anahtarları Info.plist'e ekler.
///
/// Zaten var olan anahtarlara dokunulmaz: kullanıcı bilinçli olarak
/// değiştirmiş olabilir.
PatchResult patchInfoPlist(String plist, String additions) {
  if (plist.contains('GADApplicationIdentifier')) {
    return PatchResult(plist);
  }

  final index = plist.lastIndexOf('</dict>');
  if (index == -1) {
    return PatchResult(plist, problem: 'Info.plist beklenen yapıda değil.');
  }

  final block = additions.endsWith('\n') ? additions : '$additions\n';
  return PatchResult(plist.replaceRange(index, index, block));
}

// ------------------------------------------------------------- project.pbxproj

/// PrivacyInfo.xcprivacy için sabit Xcode nesne kimlikleri.
///
/// Sabit olmaları bilinçli: aynı proje iki kez üretildiğinde dosya birebir
/// aynı olsun. Xcode'un ürettiği kimliklerle çakışma riski yok, çünkü bu
/// önek Xcode'un rastgele üreticisinden gelmiyor.
const _privacyFileRefId = 'F0F0E1E1000000000000FE01';
const _privacyBuildFileId = 'F0F0E1E1000000000000FE02';

/// PrivacyInfo.xcprivacy dosyasını Xcode projesine kaydeder.
///
/// Dosyayı diske koymak YETMEZ: Xcode'a kayıtlı değilse uygulama paketine
/// kopyalanmaz, Apple onu göremez ve dosyayı eklemiş olmanız hiçbir işe
/// yaramaz. Sessizce başarısız olan bir durumdur, bu yüzden otomatikleştirilir.
PatchResult registerPrivacyManifest(String pbxproj) {
  if (pbxproj.contains('PrivacyInfo.xcprivacy')) {
    return PatchResult(pbxproj);
  }

  var content = pbxproj;

  const buildFileAnchor = '/* Begin PBXBuildFile section */\n';
  const fileRefAnchor = '/* Begin PBXFileReference section */\n';
  if (!content.contains(buildFileAnchor) || !content.contains(fileRefAnchor)) {
    return PatchResult(pbxproj,
        problem: 'project.pbxproj beklenen bölümleri içermiyor.');
  }

  content = content.replaceFirst(
    buildFileAnchor,
    '$buildFileAnchor\t\t$_privacyBuildFileId /* PrivacyInfo.xcprivacy in '
    'Resources */ = {isa = PBXBuildFile; fileRef = $_privacyFileRefId '
    '/* PrivacyInfo.xcprivacy */; };\n',
  );

  content = content.replaceFirst(
    fileRefAnchor,
    '$fileRefAnchor\t\t$_privacyFileRefId /* PrivacyInfo.xcprivacy */ = '
    '{isa = PBXFileReference; lastKnownFileType = text.plist.xml; '
    'path = PrivacyInfo.xcprivacy; sourceTree = "<group>"; };\n',
  );

  // Runner grubuna ekle — dosya Xcode'un kenar çubuğunda görünsün.
  final group = RegExp(
    r'([0-9A-F]{24} /\* Runner \*/ = \{\s*\n\s*isa = PBXGroup;\s*\n\s*children = \(\n)',
  ).firstMatch(content);
  if (group == null) {
    return PatchResult(pbxproj, problem: 'Xcode projesinde Runner grubu bulunamadı.');
  }
  content = content.replaceRange(
    group.end,
    group.end,
    '\t\t\t\t$_privacyFileRefId /* PrivacyInfo.xcprivacy */,\n',
  );

  // Asıl iş bu: Copy Bundle Resources fazına eklemek. Grup üyeliği
  // dosyayı pakete SOKMAZ.
  RegExpMatch? target;
  for (final match in RegExp(
    r'isa = PBXResourcesBuildPhase;[\s\S]*?files = \(\n',
  ).allMatches(content)) {
    if (_resourcesBlockHasStoryboard(content, match.end)) {
      target = match;
      break;
    }
  }
  if (target == null) {
    return PatchResult(pbxproj,
        problem: 'Xcode projesinde Copy Bundle Resources fazı bulunamadı.');
  }
  content = content.replaceRange(
    target.end,
    target.end,
    '\t\t\t\t$_privacyBuildFileId /* PrivacyInfo.xcprivacy in Resources */,\n',
  );

  return PatchResult(content);
}

/// Birden çok Resources fazı vardır (uygulama ve test hedefi); doğru olan,
/// içinde uygulamanın kaynaklarının bulunduğudur.
bool _resourcesBlockHasStoryboard(String content, int start) {
  final end = content.indexOf(');', start);
  if (end == -1) return false;
  return content.substring(start, end).contains('LaunchScreen.storyboard');
}

// ------------------------------------------------------- AndroidManifest.xml

/// Ana manifeste INTERNET izni, AdMob uygulama kimliği ve uygulama adını ekler.
PatchResult patchAndroidManifest(
  String manifest, {
  required String appLabel,
  String? admobAppId,
}) {
  var content = manifest;

  if (!content.contains('android.permission.INTERNET')) {
    final index = content.indexOf('    <application');
    if (index == -1) {
      return PatchResult(manifest,
          problem: 'AndroidManifest.xml beklenen yapıda değil.');
    }
    // Flutter bu izni yalnızca debug/profile derlemelerine kendiliğinden
    // ekler; ana manifestte yoksa ağ SADECE sürüm derlemesinde sessizce
    // çalışmaz.
    content = content.replaceRange(
      index,
      index,
      '    <!-- Flutter bu izni yalnızca debug/profile derlemelerine\n'
      '         kendiliğinden ekler; burada olmazsa ağ istekleri SADECE\n'
      '         sürüm derlemesinde sessizce başarısız olur. -->\n'
      '    <uses-permission android:name="android.permission.INTERNET"/>\n\n',
    );
  }

  content = content.replaceFirst(
    RegExp(r'android:label="[^"]*"'),
    'android:label="$appLabel"',
  );

  if (admobAppId != null && !content.contains('gms.ads.APPLICATION_ID')) {
    final index = content.indexOf('    </application>');
    if (index == -1) {
      return PatchResult(content,
          problem: 'AndroidManifest.xml içinde </application> bulunamadı.');
    }
    content = content.replaceRange(
      index,
      index,
      '        <!-- AdMob uygulama kimliği. Şu anki değer Google\'ın TEST\n'
      '             kimliğidir; yayına çıkmadan önce gerçek kimlikle\n'
      '             değiştirin. Test kimliğiyle yayınlanan uygulama\n'
      '             sorunsuz çalışır ve HİÇ gelir getirmez. -->\n'
      '        <meta-data\n'
      '            android:name="com.google.android.gms.ads.APPLICATION_ID"\n'
      '            android:value="$admobAppId" />\n',
    );
  }

  return PatchResult(content);
}

// ------------------------------------------------------- build.gradle.kts

/// Sürüm imzalamasını key.properties dosyasından okur hâle getirir.
PatchResult patchBuildGradle(
  String gradle, {
  required String prelude,
  required String signingConfigs,
}) {
  if (gradle.contains('key.properties')) return PatchResult(gradle);

  var content = gradle;

  if (!content.contains('import java.util.Properties')) {
    content = 'import java.util.Properties\n\n$content';
  }

  // Eklentilerden sonra, android bloğundan önce.
  final androidBlock = content.indexOf('\nandroid {');
  if (androidBlock == -1) {
    return PatchResult(gradle,
        problem: 'build.gradle.kts içinde android bloğu bulunamadı.');
  }
  content = content.replaceRange(
    androidBlock + 1,
    androidBlock + 1,
    '$prelude\n',
  );

  // flutter create'in ürettiği buildTypes bloğu debug anahtarını kullanır;
  // Play Console bu paketi reddeder. Blok bütünüyle değiştirilir.
  final defaultBuildTypes = RegExp(
    r'\n {4}buildTypes \{\n[\s\S]*?\n {4}\}\n',
  );
  if (!defaultBuildTypes.hasMatch(content)) {
    return PatchResult(content,
        problem: 'build.gradle.kts içinde buildTypes bloğu bulunamadı.');
  }
  content = content.replaceFirst(defaultBuildTypes, '\n$signingConfigs');

  return PatchResult(content);
}

/// Android `applicationId`'yi verilen kimliğe eşitler.
///
/// `flutter create`, alt çizgili proje adlarında iki mağazaya farklı kimlik
/// üretir: Android alt çizgiyi korur, Apple bundle ID'de alt çizgiye izin
/// vermediği için iOS camelCase alır (yazi_tara → yaziTara). Ortak kimlik
/// olarak iOS'unki seçilir — Android her iki biçimi de kabul eder, Apple
/// etmez. Hem `.kts` (`applicationId = "..."`) hem Groovy
/// (`applicationId "..."`) sözdizimini tanır.
PatchResult patchAndroidApplicationId(String gradle, String id) {
  final pattern = RegExp(r'''(applicationId\s*=?\s*)["'][^"']+["']''');
  if (!pattern.hasMatch(gradle)) {
    return PatchResult(gradle,
        problem: 'build.gradle içinde applicationId bulunamadı.');
  }
  return PatchResult(
    gradle.replaceFirstMapped(pattern, (m) => '${m.group(1)}"$id"'),
  );
}

// -------------------------------------------------------------- pubspec.yaml

/// pubspec.yaml'ı yayına uygun hâle getirir.
///
/// `flutter create` sürümü `1.0.0+1` yazar ama açıklamayı şablon metniyle
/// bırakır ve ikon/açılış ekranı yapılandırması koymaz.
String patchPubspec(
  String pubspec, {
  required String description,
  required String projectName,
}) {
  var content = pubspec.replaceFirst(
    RegExp(r'^description:.*$', multiLine: true),
    'description: "$description"',
  );

  content = content.replaceFirst(
    RegExp(r'^version:.*$', multiLine: true),
    '# Biçim: <sürüm adı>+<build numarası>\n'
    '# Build numarası deploy.sh tarafından her yayında otomatik artırılır ve\n'
    '# hem iOS (CURRENT_PROJECT_VERSION) hem Android (versionCode) için tek\n'
    '# kaynaktır. Elle dokunmayın.\n'
    'version: 1.0.0+1',
  );

  if (!content.contains('flutter_launcher_icons:')) {
    content = '$content\n${_iconConfig(projectName)}';
  }

  return content;
}

String _iconConfig(String projectName) => '''
# Uygulama ikonu. Kaynak görsel 1024x1024 PNG olmalı ve saydamlık
# İÇERMEMELİ — App Store saydam ikonu reddeder.
# Yeniden üretmek için:  dart run flutter_launcher_icons
flutter_launcher_icons:
  image_path: "assets/icon/icon.png"
  android: true
  adaptive_icon_background: "#2F6FED"
  adaptive_icon_foreground: "assets/icon/icon_foreground.png"
  ios: true
  remove_alpha_ios: true

# Açılış ekranı; yeniden üretmek için:
#   dart run flutter_native_splash:create
flutter_native_splash:
  color: "#2F6FED"
  image: assets/icon/icon_foreground.png
  android: true
  ios: true
  android_12:
    color: "#2F6FED"
    image: assets/icon/icon_foreground.png
''';
