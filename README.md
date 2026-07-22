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
