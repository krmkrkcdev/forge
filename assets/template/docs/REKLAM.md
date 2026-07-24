# Reklam standardı

Bu dosya bütün uygulamalarda **aynıdır**. Reklam kararları uygulama başına
yeniden verilmez; burada bir kez verilir ve her yeni uygulama bunu devralır.

Kod tarafı iki dosyadan ibarettir ve ikisi de olduğu gibi kopyalanır:

```
lib/services/ad_service.dart   kimlikler, onay akışı, sıklık kuralı
lib/widgets/banner_ad_slot.dart  banner yuvası
```

## Biçimler

| Biçim | Kullanılır mı | Neden |
|---|---|---|
| Banner | ✅ | Kaydırılan içeriğin **sonunda**, tek yerde |
| Geçiş (interstitial) | ✅ | Yalnızca kullanıcı bir işi TAMAMLADIĞINDA |
| Ödüllü (rewarded) | Duruma göre | Kullanıcı ne aldığını bilerek başlatır; en az rahatsız eden biçim |
| Uygulama açılış (app open) | ❌ | Kullanıcı uygulamayı bir iş için açar; açılışta reklam görmek kaldırma sebebidir |
| Yerleşik (native) reklam | ❌ | İçerik sanılıp yanlışlıkla tıklanır; hem kullanıcıya hem hesaba zarar |

## Yerleşim kuralları

1. **Reklam işin ortasına girmez.** Geçiş reklamı yalnızca "tamamlandı"
   anında çıkar; oluşturma ve düzenleme akışlarının ortasında asla.
2. **Sıklık sınırı koddadır, ekranda değil.** 4 değerli eylemde bir, iki
   reklam arasında en az 5 dakika, uygulama açıldıktan sonraki ilk 45
   saniyede hiç.
3. **Banner ekranda tek yerdedir** ve dokunulabilir öğelerin bitişiğine
   konmaz. Yanlış tıklama Google'ın politika ihlali listesindedir; tekrarı
   hesabın kapatılmasıyla sonuçlanır.
4. **Yüklenmemiş reklam yer kaplamaz.** Boş kutu bırakmak düzeni zıplatır.
5. **Premium reklamları anında kaldırır.** Satın alma bittiği anda; yeniden
   başlatma gerekmez.

## Kimlikler

İki ayrı kimlik türü vardır ve karıştırılması en sık yapılan hatadır:

| Tür | Biçim | Nerede yazar |
|---|---|---|
| Uygulama kimliği | `ca-app-pub-XXX~YYY` (tilde) | `Info.plist` ve `AndroidManifest.xml` |
| Reklam birimi kimliği | `ca-app-pub-XXX/YYY` (bölü) | Koda `--dart-define` ile |

Reklam birimi kimlikleri koda gömülmez; `.env` dosyasından `deploy.sh`
aracılığıyla `--dart-define` olarak geçer. Verilmezse kod Google'ın **test**
kimliklerine düşer.

> **Gerçek kimliklerle geliştirme yapıp kendi reklamınıza tıklamayın.**
> AdMob bunu geçersiz trafik sayar ve hesabı kapatır; karar temyiz edilemez.
> Varsayılanın test kimliği olması bu yüzden bilinçli bir tercihtir.

Karşı taraftaki tuzak da gerçektir: **yayına test kimliğiyle çıkmak.**
Uygulama çalışır, reklamlar görünür, hiçbir hata mesajı yoktur — yalnızca
gelir sıfırdır ve bunu ancak haftalar sonra fark edersiniz. `forge doctor`
her iki platformun uygulama kimliğini de denetler.

## Onay (UMP) — atlanamaz

Avrupa Birliği ve İngiltere'deki kullanıcılara onay formu göstermek
zorunludur. `AdService.init()` bunu kendisi yürütür:

```
onay bilgisini güncelle → gerekiyorsa formu göster → canRequestAds()
```

Onay yoksa SDK hiç başlatılmaz ve reklam istenmez; uygulama reklamsız
çalışmaya devam eder. **Reklam hiçbir zaman uygulamanın çalışma şartı
değildir.**

Formun görünmesi için AdMob konsolunda bir mesaj tanımlanmış olmalıdır:
*Privacy & messaging → GDPR → yayınla.* Konsolda mesaj yoksa kod doğru
çalışsa bile form çıkmaz.

Ayrıca ayarlar ekranına **gizlilik seçenekleri** satırı eklenmelidir:

```dart
ValueListenableBuilder<bool>(
  valueListenable: AdService.instance.privacyOptionsRequired,
  builder: (context, required, _) => required
      ? ListTile(
          title: const Text('Reklam gizlilik seçenekleri'),
          onTap: AdService.instance.showPrivacyOptions,
        )
      : const SizedBox.shrink(),
)
```

Gerekli olduğu hâlde bu satırın bulunmaması politika ihlalidir.

## iOS tarafı

- `Info.plist` → `GADApplicationIdentifier` (gerçek uygulama kimliği)
- `Info.plist` → `SKAdNetworkItems`: yükleme ilişkilendirmesi bunsuz
  çalışmaz, doğrudan geliri düşürür. Listeyi Google'ın belgesinden alın.
- `PrivacyInfo.xcprivacy` → reklam SDK'sı cihaz kimliği ve kullanım verisi
  toplar; bu **beyan edilmelidir** ve App Store Connect gizlilik anketiyle
  tutarlı olmalıdır.
- İzleme izni (ATT) istemiyorsanız `NSPrivacyTracking` `false` kalır ve
  reklamlar kişiselleştirilmez. İstemek eCPM'i yükseltir ama
  `app_tracking_transparency` paketi ve `NSUserTrackingUsageDescription`
  gerektirir; bu ayrı bir karardır.

## Android tarafı

- `AndroidManifest.xml` → `com.google.android.gms.ads.APPLICATION_ID`
- Play Console → Uygulama içeriği → **Reklamlar: evet**. Beyan edilmeyen
  reklam, uygulamanın yayından kaldırılma sebebidir.

## Mağaza beyanları

| Mağaza | Yapılacak beyan |
|---|---|
| App Store Connect | Gizlilik anketi: Tanımlayıcılar → Cihaz Kimliği; Kullanım Verisi → Reklam Verisi |
| Play Console | Uygulama içeriği → Reklamlar: **Evet** |
| Play Console | Veri güvenliği formu: reklam SDK'sının topladığı veriler |

Bu üç beyan da eksikse uygulama yayından kaldırılır. Kod tarafı kusursuz
olsa bile.
