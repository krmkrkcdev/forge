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
| `ITSAppUsesNonExemptEncryption` | Uyarı | Her yüklemede elle soru |
| `PrivacyInfo.xcprivacy` varlığı | Uyarı | Apple zorunlu tutuyor |
| Paket kimliği tutarlılığı | Uyarı | Derin bağlantı ve analitikte karışıklık |
| Özel uygulama ikonu | Uyarı | İnceleme reddi riski |
| Sürümde düz metin HTTP | Uyarı | Trafik şifresiz gider |

Yeni bir tuzağa düştüğünüzde `lib/src/checks.dart` içine bir kural ekleyin.

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

## Ajan kuralları

`assets/AGENTS.md.template`, projelerinizde çalışan yapay zekâ ajanları için
hazır bir kural dosyasıdır: mimari ilkeler, doğrulama adımları, yayın akışı ve
bilinen tuzaklar. Yeni projeye kopyalayıp `{{APP_NAME}}` yerine uygulama adını
yazın.

Önemli kural: **ajan mağazaya yükleme yapmaz.** Geri alınamaz ve dışa dönük
bir işlemdir; gerçek yüklemeyi insan başlatır.

## Yol haritası

- [x] `forge doctor` — mağaza hazırlık denetimi
- [x] `forge fix` — otomatik düzeltmeler
- [ ] `forge new` — Flutter + FastAPI + Docker + deploy iskeleti üretimi
- [ ] `forge release` — deploy.sh sarmalayıcısı
- [ ] `forge icon` — tek görselden ikon ve açılış ekranı üretimi
