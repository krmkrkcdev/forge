# forge

Flutter uygulamalarını hızlıca üretip mağazaya taşımak için komut satırı aracı.

Vaktinde'yi yayına hazırlarken karşılaşılan her engel burada kalıcı bir kurala
dönüştürülmüştür. Amaç aynı tuzağa ikinci kez düşmemek.

## Kurulum

```bash
dart pub global activate --source path .
```

Ardından `forge` komutu her yerde çalışır. (`~/.pub-cache/bin` PATH'te olmalı.)

> **Kaynağı her değiştirdiğinizde bu komutu tekrar çalıştırın.** Kurulum bir
> anlık görüntüdür; kaynağı düzenlemek onu güncellemez. `deploy.sh` yayın
> öncesi PATH'teki forge'u çağırdığı için, yeni eklediğiniz bir denetim eski
> kurulumda hiç çalışmaz ve çıktı yanıltıcı biçimde "temiz" görünür — gerçekten
> başımıza geldi. `forge doctor` artık bunu fark edip uyarıyor, panelde de
> **🔁 forge'u yeniden kur** düğmesi var.

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

### Hesap varsayılanları

Makine başına bir kez girilen, her projede aynı olan değerler
`~/.forge/account.json` içinde durur (panel yazar). `forge new` bunlardan
**`APPLE_TEAM_ID`**'yi okuyup Xcode projesine yazar.

Sebebi: takım seçilmeden provisioning profile üretilemez, dolayısıyla arşiv
de alınamaz. `flutter create` bu alanı boş bırakır ve her yeni proje aynı
engelle açılırdı. Değer yoksa adım atlanır ve sebebi ekrana yazılır —
sessizce geçip kullanıcıyı `forge doctor` çıktısında şaşırtmak yerine.

Var olan bir takım kimliğinin üzerine yazılmaz: o alan sizin kararınızdır.

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

### `forge analyze`

Bağımlılıkları çözer ve `flutter analyze` çalıştırır.

```bash
forge analyze                  # bulunduğun dizinden yukarı doğru proje arar
forge analyze --path app
forge analyze --no-pub-get     # bağımlılıklar zaten çözülüyse
```

`forge doctor` mağaza hazırlığına bakar — dosyalar, kimlikler, beyanlar;
kodun kendisine bakmaz. Analiz hatası olan proje `deploy.sh` içinde de
yakalanır ama **dakikalar sonra**: temizlik ve derleme harcandıktan, tam
imzalama adımının öncesinde. Bu komut aynı bilgiyi saniyeler içinde verir.

`pub get` varsayılan olarak önce çalışır: bağımlılıklar çözülmeden yapılan
analiz her import için "target of URI doesn't exist" üretir — yeni paket
ekledikten sonra en sık düşülen tuzak budur.

Üretim yayınında (`./deploy.sh <platform> release`) analiz zorunludur;
beta'da çalıştırılmaz, hızlı tur atmak meşrudur.

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
| UMP formu var, ATT izni istenmiyor | Engel | Apple UMP formunu "özel izleme ekranı" sayar: 5.1.2(i) reddi |
| ATT paketi eklenmiş, çağrı yapılmamış | Engel | Paketi eklemek diyaloğu göstermez; aynı redde geri dönülür |
| `NSPrivacyTracking` ile kodun çelişmesi | Engel | Yanlış beyan; iki yönü de reddedilir |
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
| PATH'teki forge kaynaktan eski mi | Uyarı | Yeni eklenen denetim hiç çalışmaz, çıktı yanıltıcı biçimde "temiz" görünür |

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

## Backend (`forge new --backend`)

İsteğe bağlı bir sunucu katmanı üretir: **FastAPI + PostgreSQL + Docker**.
Panelde "Yeni uygulama" formundaki **Backend ekle** kutusu da aynı şeyi yapar.

```bash
forge new not_defteri --org com.sirket --backend
cd not_defteri/backend
cp .env.example .env && openssl rand -base64 24   # POSTGRES_PASSWORD, bir kez
docker compose up -d --build                      # API 127.0.0.1:8000, /docs
```

Üretilen `docker-compose.yml` aynı sunucuda birden çok servis barındırmaya
göre kuruludur; dördü de gerçek olaylardan doğmuş kararlardır:

- `name: <proje>` — ad verilmezse Docker onu klasör adından türetir ve
  compose'unu `backend/` altında tutan iki proje aynı ada düşer: ikincisi
  ilkinin konteynerlerini siler, veritabanını devralır, imajını ezer.
- `container_name: <proje>-api` — ters vekil servise bu adla bağlanır.
- `127.0.0.1:${API_PORT:-8000}:8000` — API dışarıya değil yalnızca localhost'a
  bağlanır; her servise `.env` içinden ayrı port verilir.
- `proxy` ağı `external` — ters vekil ile ortak ağ, adı `PROXY_NETWORK`.

`POSTGRES_PASSWORD` yığın bir kez ayağa kalktıktan sonra değiştirilmez:
Postgres ilk kurulumdaki parolayı saklar, sonradan değişeni yok sayar ve API
"password authentication failed" ile restart döngüsüne girer.

Felsefe `AGENTS.md`'deki ile aynı — **çevrimdışı öncelikli**: telefondaki
veritabanı ana kaynak, sunucu bir yedek ve senkron katmanı. Bu yüzden uçlar
sade: `GET /health`, `POST /sync/push` (son-yazan-kazanır), `GET /sync/pull`.
Kimlikler istemcide üretilir, silmeler mezar taşıyla senkronlanır.

Üretilen `backend/` kendi testiyle gelir (docker gerekmeden, bellek içi SQLite):
`cd backend && pip install -r requirements-dev.txt && pytest`. Ayrıca app
tarafına `test/api_contract_test.dart` konur — çalışan sunucuya karşı koşar.

Çekirdek iskelettir; kimlik doğrulama, yeni kaynaklar ve gelişmiş çakışma
çözümü `backend/README.md`'de anlatıldığı gibi üzerine eklenir.

## Kontrol paneli

Komut satırının tamamı tarayıcıdan da yönetilebilir. Panel, forge'un yaptığı
her işi (denetle, düzelt, güncelle, build al, yayınla, yeni proje başlat) tek
ekranda toplar ve çıktıyı canlı akıtır.

```bash
dart run dashboard/serve.dart
```

Tarayıcı `http://localhost:4577` adresinde kendiliğinden açılır. Panel üst
dizindeki bütün Flutter projelerini tarar; başka bir kök için `--base <dizin>`.

Ne yapar:

| Bölüm | İş |
|---|---|
| **Yol Haritası** | Oluşturmadan incelemeye 9 adımlık sıralı rehber. Panelin izlediği maddeler otomatik ✓; konsollarda elle yapılanlar (ASC kaydı, App Privacy, testçi, Data safety…) işaretlenir ve hatırlanır. ASC/Play'in doldurulacak TÜM alanları içeride |
| **Yayına hazırlık** | iOS ve Android yolları **ayrı** değerlendirilir — Android'deki eksik iOS yayınını bekletmez. Her platformun kendi "ne kaldı" listesi; maddelerden ilgili yere atlanır |
| **Denetim** | `forge doctor` sonuçları platforma göre gruplu (iOS / Android / Ortak); `forge fix` deneme ve uygulama |
| **İkon** | Tek görsel yükle → iOS+Android ikon, adaptive ikon, açılış ekranı üretilir (`forge icon`) |
| **Geliştirme** | `flutter pub get` / `pub upgrade` |
| **Build & Yayın** | iOS ve Android **ayrı kartlar**: build (deneme), TestFlight / Play Beta, App Store / Play'e **yükleme** (yayını insan yapar) |
| **Yapılandırma** | Uygulamanın anahtarlarını (`.env`) tarayıcıdan doldur — App Store Connect, Google Play, AdMob, backend. Her alanda *nereden alınır* linki; `.p8`/JSON dosyaları sürükle-yükle |
| **Yeni uygulama** | `forge new` formu — ad, kimlik, görünen ad, açıklama, GitHub'da repo aç |

İki tasarım kararı bilinçlidir:

- **Yalnızca localhost.** Panel kabuk komutu çalıştırır; dış ağa açılırsa
  makineyi başkasının eline verir. Dinleme adresi sabittir, değiştirilemez.
- **Gerçek yayın iki kapıdan geçer.** Geri alınamaz bir yükleme başlatmadan
  önce panel onay ister _ve_ sunucu `confirm=YAYINLA` olmadan reddeder.
  Tarayıcıdaki onay tek başına güvenilmez sayılır.

## Yol haritası

- [x] `forge doctor` — mağaza hazırlık denetimi
- [x] `forge fix` — otomatik düzeltmeler
- [x] `forge new` — mağazaya hazır proje iskeleti
- [x] Kontrol paneli — denetim, build ve yayının tarayıcıdan yönetimi
- [x] `forge new --backend` — FastAPI + PostgreSQL + Docker katmanı
- [ ] `forge release` — deploy.sh sarmalayıcısı
- [x] `forge icon` — tek görselden ikon ve açılış ekranı üretimi
- [ ] `forge screenshots` — mağaza ekran görüntülerini simülatörden üretme
