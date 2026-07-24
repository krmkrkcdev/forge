# forge

Flutter uygulamalarını hızlıca üretip mağazaya taşımak için komut satırı aracı.

Vaktinde'yi yayına hazırlarken karşılaşılan her engel burada kalıcı bir kurala
dönüştürülmüştür. Amaç aynı tuzağa ikinci kez düşmemek.

## Kurulum

```bash
dart pub global activate --source path .
```

Ardından `forge` komutu her yerde çalışır. (`~/.pub-cache/bin` PATH'te olmalı.)

## Komutlar

### `forge new`

Mağazaya hazır bir proje üretir.

```bash
forge new not_defteri --org com.sirketiniz --app-name "Not Defteri"
```

`flutter create` iyi bir başlangıç noktası verir ama mağazaya hazır bir proje
vermez: sürüm derlemesi debug anahtarıyla imzalanır, ana manifestte INTERNET
izni yoktur, gizlilik manifesti yoktur, yayın akışı yoktur. `forge new`
aradaki farkı kapatır.

Üretilen yapı:

```
not_defteri/
  AGENTS.md               ajan kuralları
  docs/REKLAM.md          reklam standardı
  .gitignore              sır desenleri dahil
  app/
    deploy.sh             yayın akışı (+ fastlane yapılandırması)
    .env.example
    lib/services/ad_service.dart      ← her uygulamada AYNI
    lib/widgets/banner_ad_slot.dart   ← her uygulamada AYNI
    ios/Runner/PrivacyInfo.xcprivacy  (Xcode projesine kayıtlı)
    android/key.properties.example
```

Üretilen projede `forge doctor` **sıfır engelle** çıkar. Geriye kalan
uyarılar bilinçli olarak sizin kararınız olan şeylerdir: imzalama anahtarı,
uygulama ikonu ve gerçek AdMob kimlikleri.

| Seçenek | Anlamı |
|---|---|
| `--org` | Ters alan adı. **Zorunlu** — paket kimliği bundan türer ve yayınlandıktan sonra değişmez. |
| `--app-name` | Kullanıcının gördüğü ad. Verilmezse proje adından türetilir. |
| `--path` | Hedef dizin. Varsayılan `./<ad>`. |
| `--no-pub-add` | Bağımlılıkları eklemez (ağsız ortam). |
| `--no-git` | Depo başlatmaz. |

### `forge doctor`

Projeyi App Store ve Play Store yayınına hazır mı diye denetler.

```bash
forge doctor                    # bulunduğun dizinden yukarı doğru proje arar
forge doctor --path app         # belirli bir proje
forge doctor --strict           # uyarıları da hata sayar (CI için)
```

Çıkış kodu: engel varsa `1`, temizse `0`. Yayın betiğine ya da CI'a
takılabilir.

Her bulgu üç şey söyler: **ne** yanlış, **neden** önemli, **nasıl** düzeltilir.
"Neden" kısmı bilinçli olarak vardır — sebebi anlaşılmayan uyarı görmezden
gelinir.

### `forge fix`

Tek doğru cevabı olan düzeltmeleri uygular.

```bash
forge fix --dry-run   # neyin değişeceğini gösterir
forge fix
```

Bilinçli olarak dar tutulmuştur. İmzalama anahtarı üretmek veya paket kimliği
seçmek gibi **kararlar size aittir**; araç bunları sizin yerinize vermez.

## Denetlenen kurallar

| Kural | Ciddiyet | Neden var |
|---|---|---|
| Sır dosyaları .gitignore'da mı | Engel | Sızan imzalama anahtarı geri alınamaz |
| iOS imzalama takımı seçili mi | Engel | Takımsız arşiv alınamaz |
| Sürümde build numarası | Engel | Yayın betiği yoksa hiç başlamaz |
| Android debug imzalama | Engel | Play Console reddeder |
| Ana manifestte INTERNET izni | Engel | Ağ yalnızca sürüm derlemesinde çalışmaz |
| iOS izin açıklamaları | Engel | Uygulama çalışma anında çöker |
| Varsayılan `com.example` kimliği | Engel | Mağazalar kabul etmez |
| PrivacyInfo Xcode'a kayıtlı mı | Engel | Dosya pakete girmez, sessizce işe yaramaz |
| AdMob uygulama kimliği eksik | Engel | Reklam SDK'sı açılışta uygulamayı çökertir |
| iPad yön beyanı tutarsızlığı | Engel | Yükleme 90474 hatasıyla reddedilir |
| `NSUserTrackingUsageDescription` | Engel | ATT izni isteyen uygulama çalışma anında çöker |
| `ITSAppUsesNonExemptEncryption` | Uyarı | Her yüklemede elle soru |
| `PrivacyInfo.xcprivacy` varlığı | Uyarı | Apple zorunlu tutuyor |
| Paket kimliği tutarlılığı | Uyarı | Derin bağlantı ve analitikte karışıklık |
| Özel uygulama ikonu | Uyarı | İnceleme reddi riski |
| İkon kaynak görselinin varlığı | Uyarı | Yapılandırma var, üretim hiç çalışmamış |
| Sürümde düz metin HTTP | Uyarı | Trafik şifresiz gider |
| AdMob **test** uygulama kimliği | Uyarı | Uygulama çalışır, gelir sıfırdır — geri bildirim vermeyen hata |
| Reklam onayı (UMP) hiç istenmiyor | Uyarı | AB'de reklam sunulmaz, politika ihlali |
| `SKAdNetworkItems` eksikliği | Uyarı | Yükleme ilişkilendirilemez, eCPM düşer |
| Gizlilik manifesti reklamdan söz etmiyor | Uyarı | Beyan gerçekle uyuşmaz, red sebebi |

Yeni bir tuzağa düştüğünüzde `lib/src/checks.dart` içine bir kural ekleyin.

Üretim yayınında (`./deploy.sh <platform> release`) uyarılar da engel
sayılır. Beta'da sayılmaz: TestFlight'a test reklam kimliğiyle çıkmak
meşrudur, mağazaya çıkmak değildir.

### Ortam denetimleri

Proje dosyaları kusursuz olsa bile yayın, kurulu araç zinciri yüzünden
durabilir. Bu yüzden `forge doctor` çıktısında ayrı bir **Ortam** bölümü var —
bilinçli olarak ayrı bir komut değil, çünkü ayrı bayrağa konsa tam da
unutulacağı yerde olurdu.

| Kural | Ciddiyet | Neden var |
|---|---|---|
| iOS SDK mağaza eşiğinin üstünde mi | Engel | Eski SDK ile üretilen paket reddedilir |
| LANG/LC_ALL UTF-8 mi | Uyarı | CocoaPods ve fastlane sebebi anlaşılmaz hatayla çöker |

Apple, kabul ettiği en düşük SDK sürümünü periyodik olarak yükseltir; eşik
`lib/src/environment.dart` içinde `minimumIosSdkMajor` sabitidir.

## Testler

```bash
dart test
```

Mantık içeren kuralların testi vardır: sır sızıntısı denetimi gerçek bir git
deposu kurup `git check-ignore` davranışını sınar, sahte nesne kullanmaz.

## Şablonlar

`assets/template/` altındaki dosyalar `forge new`'ün ürettiği projenin
kaynağıdır. Orada düzenlenir; sonra koda gömülür:

```bash
dart run tool/bundle_assets.dart
```

Gömme adımı gerekli çünkü küresel olarak kurulan `forge` bir anlık
görüntüdür ve yanındaki `assets/` dizinini güvenilir biçimde bulamaz.
Adımı unutursanız `dart test` yakalar.

Şablonun içinde iki dosya özeldir — **her uygulamada aynıdır** ve uygulama
başına değiştirilmez:

```
lib/services/ad_service.dart
lib/widgets/banner_ad_slot.dart
```

Reklam kuralları (biçimler, yerleşim, sıklık, onay akışı, mağaza beyanları)
`assets/template/docs/REKLAM.md` içinde bir kez karara bağlanmıştır.
Değişiklik uygulamaya değil, standarda yapılır.

## Ajan kuralları

`assets/template/AGENTS.md`, projelerinizde çalışan yapay zekâ ajanları için
hazır bir kural dosyasıdır: mimari ilkeler, doğrulama adımları, yayın akışı ve
bilinen tuzaklar. `forge new` bunu projeye kendisi koyar.

Önemli kural: **ajan mağazaya yükleme yapmaz.** Geri alınamaz ve dışa dönük
bir işlemdir; gerçek yüklemeyi insan başlatır.

## Yol haritası

- [x] `forge doctor` — mağaza hazırlık denetimi
- [x] `forge fix` — otomatik düzeltmeler
- [x] `forge new` — mağazaya hazır proje iskeleti
- [ ] `forge new --backend` — FastAPI + PostgreSQL + Docker katmanı
- [ ] `forge release` — deploy.sh sarmalayıcısı
- [ ] `forge icon` — tek görselden ikon ve açılış ekranı üretimi
- [ ] `forge screenshots` — mağaza ekran görüntülerini simülatörden üretme
