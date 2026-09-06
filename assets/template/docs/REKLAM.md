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
- `NSUserTrackingUsageDescription` → izleme izni açıklaması (aşağıya bakın)

## İzleme izni (ATT) — UMP formu bunun yerine geçmez

Bu bölüm gerçek bir redden doğdu. Yalnızca UMP formu gösteren bir sürüm
**5.1.2(i)** gerekçesiyle reddedildi:

> The app does not use App Tracking Transparency to request the user's
> permission before collecting data used to track them. Instead, the app
> displays a custom prompt that requests the user to allow tracking.

Apple'ın "özel ekran" (custom prompt) dediği şey **Google'ın UMP formuydu.**
Kod tarafında hata yoktu; eksik olan şuydu: iOS'ta reklam kimliğine (IDFA)
erişmek için Apple'ın KENDİ diyaloğu gösterilmek zorundadır. İki form
birbirinin yerine geçmez:

| Form | Kimin | Neyi sorar | Nerede zorunlu |
|---|---|---|---|
| UMP onay formu | Google | GDPR/DMA onayı | AB + İngiltere |
| ATT diyaloğu | Apple | IDFA ile izleme izni | iOS 14+, **her yerde** |

> **Tuzak:** AdMob konsolunda *Privacy & messaging → ATT* mesajı
> yayınlanmışsa Google, ATT diyaloğundan önce kendi "açıklayıcı" ekranını
> gösterir ve gerçek izni **uygulamanın** istemesini bekler. Uygulama
> istemezse kullanıcı yalnızca Google'ın ekranını görür — inceleme bunu
> "izleme izni isteyen özel ekran" sayar. Red mektubunun tarifi budur.

İzin istenecekse **dört şey birden** doğru olmalıdır; biri eksikken
diğerleri kusursuz olsa bile inceleme reddedilir:

1. `pubspec.yaml` → `app_tracking_transparency`
2. `Info.plist` → `NSUserTrackingUsageDescription` (metin yoksa uygulama
   izin istediği anda **çöker**)
3. Kod → `AppTrackingTransparency.requestTrackingAuthorization()`
4. App Store Connect gizlilik anketi → Cihaz Kimliği ve Reklam Verisi için
   "izleme amaçlı: Evet"

### `PrivacyInfo.xcprivacy` bu listede YOK — ve olmamalı

Sezgiye aykırı ama denenip öğrenildi: `NSPrivacyTracking` anahtarı **false
kalır.** İki sebep var, ikisi de pahalı:

1. **Apple boş listeyi reddeder.** `NSPrivacyTracking` true ise
   `NSPrivacyTrackingDomains` en az bir alan adı içermek zorundadır. Boş
   bırakılan sürüm yüklendikten sonra işleme aşamasında elenir ve sürüm
   **Invalid Binary** durumuna düşer:

   > ITMS-91064: Invalid tracking information — NSPrivacyTracking must be
   > true if NSPrivacyTrackingDomains isn't empty.

   Bunu ancak tam bir derleme + imzalama + yükleme turunu harcadıktan sonra,
   e-postayla öğrenirsiniz. `forge doctor` artık build almadan önce yakalar.

2. **Listeyi doldurmak daha kötüdür.** iOS, ATT izni **verilmemiş**
   kullanıcıda burada yazan alan adlarına giden istekleri **engeller.**
   Google'ın reklam alan adlarını yazarsanız izin vermeyen kullanıcıda
   reklamlar kişiselleştirilmemiş olarak değil, **hiç** gelmez — doğrudan
   gelir kaybı. Google zaten hangi alan adlarının yazılacağını yayımlamıyor
   ve kendi manifestinde de beyan etmiyor; SDK, ATT durumunu kendisi okuyup
   kişiselleştirmeyi ona göre kapatıyor.

Bu dosya uygulamanın **kendi ikilisinin** hangi alan adlarına izleme amaçlı
bağlandığını anlatır; reklam SDK'sının davranışını değil. İzleme beyanı ASC
anketi ve ATT diyaloğuyla yapılır.

`AdService.init()` sırası sabittir ve değiştirilmez:

```
UMP onayı → ATT diyaloğu → MobileAds.initialize()
```

ATT diyaloğu yalnızca uygulama **etkin (resumed)** durumdayken çıkar.
Açılışta, ilk kare çizilmeden istenen izin diyalog hiç görünmeden
`notDetermined` ile döner ve bir daha sorulamaz — hata mesajı da yoktur.
`AdService` bu yüzden ilk kareyi bekler.

İzin istemek istemiyorsanız alternatif bellidir: ATT çağrısı ile
`NSUserTrackingUsageDescription` kaldırılır, reklamlar kişiselleştirilmez
**ve** AdMob konsolundaki ATT mesajı yayından kaldırılır. Yayında dururken izin istememek, yukarıdaki redle
sonuçlanan durumun ta kendisidir.

## Android tarafı

- `AndroidManifest.xml` → `com.google.android.gms.ads.APPLICATION_ID`
- Play Console → Uygulama içeriği → **Reklamlar: evet**. Beyan edilmeyen
  reklam, uygulamanın yayından kaldırılma sebebidir.

## Mağaza beyanları

| Mağaza | Yapılacak beyan |
|---|---|
| App Store Connect | Gizlilik anketi: Tanımlayıcılar → Cihaz Kimliği; Kullanım Verisi → Reklam Verisi |
| App Store Connect | ATT isteniyorsa bu iki tür için **"izleme amaçlı: Evet"** — `NSPrivacyTracking=true` ile aynı hikâye |
| Play Console | Uygulama içeriği → Reklamlar: **Evet** |
| Play Console | Veri güvenliği formu: reklam SDK'sının topladığı veriler |

Bu üç beyan da eksikse uygulama yayından kaldırılır. Kod tarafı kusursuz
olsa bile.
