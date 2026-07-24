import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../services/ad_service.dart';

/// Standart banner reklam yuvası — bütün uygulamalarda AYNI dosya.
///
/// Üç kural buraya gömülüdür:
///
/// 1. **Yüklenmemiş reklam yer kaplamaz.** Boş gri kutu, reklamın kendisinden
///    daha rahatsız edicidir ve düzeni zıplatır.
/// 2. **Premium olunca anında kaybolur.** Satın alma sonrası "yeniden başlat"
///    demek zorunda kalmak, parayı ödemiş kullanıcıya yapılabilecek en kötü
///    karşılamadır.
/// 3. **İçeriğin ÜSTÜNE binmez.** Yalnızca kaydırılan içeriğin sonuna konur;
///    dokunulabilir öğelerin yanına konan reklam yanlış tıklamaya yol açar ve
///    Google bunu politika ihlali sayar.
///
/// Ekranın altına sabitlemek isterseniz `Scaffold.bottomNavigationBar`
/// yerine listenin sonuna koyun; sabit banner, klavye açıldığında ve küçük
/// ekranlarda içeriği kesiyor.
class BannerAdSlot extends StatefulWidget {
  const BannerAdSlot({super.key});

  @override
  State<BannerAdSlot> createState() => _BannerAdSlotState();
}

class _BannerAdSlotState extends State<BannerAdSlot> {
  BannerAd? _ad;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
    AdService.instance.isPremium.addListener(_onPremiumChanged);
  }

  void _onPremiumChanged() {
    if (!AdService.instance.isPremium.value) return;
    _ad?.dispose();
    _ad = null;
    if (mounted) setState(() => _loaded = false);
  }

  Future<void> _load() async {
    if (AdService.instance.isPremium.value) return;

    // init() onay akışını da yürütür; onay yoksa reklam istenmez.
    await AdService.instance.init();
    if (!mounted || !AdService.instance.isReady) return;
    if (AdService.instance.isPremium.value) return;

    final ad = BannerAd(
      adUnitId: AdService.bannerUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          if (mounted) setState(() => _loaded = false);
        },
      ),
    );
    _ad = ad;
    await ad.load();
  }

  @override
  void dispose() {
    AdService.instance.isPremium.removeListener(_onPremiumChanged);
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AdService.instance.isPremium,
      builder: (context, isPremium, _) {
        final ad = _ad;
        if (isPremium || !_loaded || ad == null) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Center(
            child: SizedBox(
              width: ad.size.width.toDouble(),
              height: ad.size.height.toDouble(),
              child: AdWidget(ad: ad),
            ),
          ),
        );
      },
    );
  }
}
