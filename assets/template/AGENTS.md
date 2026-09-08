# {{APP_NAME}} — Ajan Kuralları

Bu dosya, bu depoda çalışan yapay zekâ ajanları içindir (Antigravity, Claude
Code, Cursor vb.). Projenin nasıl geliştirildiğini ve yayınlandığını anlatır.

> `AGENTS.md` açık bir sözleşmedir ve çoğu ajan aracı tarafından okunur.
> Kullandığınız araç farklı bir dosya bekliyorsa bu dosyaya bir sembolik bağ
> verin ya da içeriği oraya kopyalayın — kaynak tek olsun.

## Proje yapısı

```
app/       Flutter uygulaması (Android + iOS)
backend/   FastAPI + PostgreSQL sunucusu (varsa)
```

## Değişmez ilkeler

Bunlar tercih değil, bu projelerin çalışma biçimidir. Aksini yapmadan önce
insana sorun.

1. **Çevrimdışı öncelikli.** Telefondaki veritabanı ana kaynaktır. Sunucu bir
   yedek ve aktarım katmanıdır; internet yokken uygulama tam çalışmalıdır.
2. **Kimlikler istemcide üretilir.** Kayıtlar çevrimdışı oluşturulabilmeli ve
   senkronizasyondan sonra kimlikleri değişmemelidir (UUID).
3. **Senkronizasyon imleci sayaçtır, zaman damgası değil.** İstemci saatleri
   güvenilmez.
4. **Silme mezar taşı bırakır.** Yoksa diğer cihazlar silmeyi öğrenemez.
5. **Sırlar depoya girmez.** `.env`, `key.properties`, `*.jks`, `*.p8`,
   servis hesabı JSON dosyaları — hepsi `.gitignore` içindedir. Bir sırrın
   commit'lendiğinden şüphelenirseniz durun ve insana söyleyin.
6. **Kullanıcıya ne söylediğinize dikkat edin.** Arayüzdeki gizlilik metni
   verinin gerçekte nereye gittiğiyle uyuşmalıdır.
7. **Reklam kuralları uygulama başına yeniden tartışılmaz.** Biçimler,
   yerleşim ve sıklık `docs/REKLAM.md` içinde bir kez karara bağlanmıştır;
   `lib/services/ad_service.dart` ve `lib/widgets/banner_ad_slot.dart` her
   uygulamada aynı dosyadır. Değiştirmeniz gerekiyorsa önce insana sorun —
   değişiklik bu uygulamaya değil, standarda yapılır.
8. **Açılış ekranı marka standardıdır.** `lib/screens/splash_screen.dart` ve
   `assets/splash/pikelabs.png` her uygulamada aynıdır: siyah zemin,
   PikeLabs logosu, dokununca geçilir. Logo dosyası kırpılmaz, maskelenmez,
   rengiyle oynanmaz; `flutter_native_splash` zemini de aynı siyah kalır,
   yoksa açılışta renk sıçrar. Uygulamanın ilk ekranı `HomeScreen`'dir;
   açılışı atlayıp `MaterialApp.home`'u değiştirmeyin.

## Dil ve üslup

- Arayüz metinleri ve kod yorumları **Türkçe**.
- Yorumlar *ne* yaptığını değil *neden* öyle yapıldığını anlatır.
- Hata mesajları kullanıcıya ne yapacağını söyler.

## Doğrulama — bunu atlamayın

Bir işi "bitti" saymadan önce:

```bash
cd app && flutter analyze && flutter test
forge doctor --path app
```

Arayüz değişikliği yaptıysanız emülatörde **gerçekten çalıştırın** ve ekran
görüntüsüyle doğrulayın. "Derleniyor" ile "çalışıyor" aynı şey değildir.

Sunucu tarafına dokunduysanız sözleşme testlerini çalıştırın:

```bash
cd backend && docker compose up -d
cd app && flutter test test/api_contract_test.dart \
  --dart-define=CONTRACT_API_URL=http://127.0.0.1:8000
```

## Yayınlama

Yayın akışı `deploy.sh` ile yürür ve şu sırayla çalışır:

```
ön kontroller → analyze + test → build numarası artır → build → imzala → yükle
```

```bash
./deploy.sh ios beta        # TestFlight
./deploy.sh android beta    # Play Store beta
./deploy.sh all release     # ikisi birden, üretim
```

**Ajan mağazaya yükleme yapmaz.** Geri alınamaz ve dışa dönük bir işlemdir;
`--dry-run` ile doğrulayın, gerçek yüklemeyi insan başlatır.

## Sürüm numarası

Tek kaynak `app/pubspec.yaml` içindeki `version: 1.0.0+3` satırıdır. Build
numarasını `deploy.sh` artırır; elle dokunmayın.

## Sık düşülen tuzaklar

Bunların hepsi gerçekten başımıza geldi:

| Tuzak | Sonuç |
|---|---|
| Sürüm derlemesinin debug anahtarıyla imzalanması | Play Console reddeder, bir build+upload turu boşa gider |
| Ana manifestte `INTERNET` izninin olmaması | Ağ **yalnızca** sürüm derlemesinde sessizce çalışmaz |
| `ITSAppUsesNonExemptEncryption` eksikliği | Her yüklemede elle ihracat uyumluluğu sorusu |
| `PrivacyInfo.xcprivacy`'nin Xcode projesine kayıtlı olmaması | Dosya pakete girmez, sessizce işe yaramaz |
| `pubspec.yaml` sürümünde `+build` olmaması | Yayın betiği hiç başlamaz |
| Proje yolunda ASCII olmayan karakter (Windows) | Gradle ve shader derleyici başarısız olur |
| Yayına AdMob **test** uygulama kimliğiyle çıkmak | Uygulama sorunsuz çalışır, gelir sıfırdır; haftalar sonra fark edilir |
| Tek platformun reklam kimliğini doldurmayı unutmak | Aynı sonuç, yalnızca o platformda |
| UMP onay formunun eksikliği | AB kullanıcılarına reklam sunulmaz, hesap politika ihlaline düşer |
| Yaş sınıflandırması anketinde reklamın beyan edilmemesi | Apple'ın otomatik analizi reklamı görür, sürüm 2.3.6 (Accurate Metadata) ile reddedilir; reklamlı uygulamada "Advertising" EVET olmalı (Play'de: "Reklam içerir" Evet) |
| iPad hedefliyken yatay yönlerin beyan edilmemesi | App Store Connect yüklemeyi 90474 hatasıyla reddeder |
| İkili (binary) iOS pod'larının arm64-simülatör dilimi olmaması (ML Kit vb.) | Yalnız-arm64 yeni simülatörlerde bağlayıcı "built for 'iOS'" hatası verir; x86_64 destekleyen eski çalışma zamanında (ör. iOS 17.x, Rosetta) ya da gerçek cihazda test edin — cihaz ve mağaza derlemeleri etkilenmez |
| `flutter build ios --simulator` çıktısının x86_64 olması | Yalnız-arm64 simülatöre kurulum "Failed to find matching arch" ile reddedilir; simülatör için `flutter run -d <udid>` kullanın |

`forge doctor` bunların hepsini denetler (simülatör satırları hariç — onlar
geliştirme ortamı tuzağıdır, yayını etkilemez). Yeni bir tuzağa düşerseniz çözümünü
`forge`'a kural olarak ekleyin — bir daha aynı yerde takılmayın.
