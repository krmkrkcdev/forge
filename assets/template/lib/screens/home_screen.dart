import 'package:flutter/material.dart';

import '../services/ad_service.dart';
import '../widgets/banner_ad_slot.dart';

/// Başlangıç ekranı.
///
/// Burada duran her şey silinip yerine uygulamanız yazılacak. Yalnızca iki
/// şeyi koruyun: listenin sonundaki [BannerAdSlot] ve gizlilik seçenekleri
/// satırı. İkisinin de gerekçesi docs/REKLAM.md içinde.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('{{APP_NAME}}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'Buradan başlayın.\n\n'
                'Yayına çıkmadan önce:  forge doctor',
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Reklam gizlilik seçenekleri. Yalnızca gerekli olduğu bölgelerde
          // (AB/İngiltere) görünür; gerekli olduğu hâlde gösterilmemesi
          // Google'ın yayıncı politikasının ihlalidir.
          const PrivacyOptionsTile(),

          // Banner her zaman kaydırılan içeriğin SONUNDA durur; yüklenmemişse
          // hiç yer kaplamaz.
          const BannerAdSlot(),
        ],
      ),
    );
  }
}

/// Ayarlar ekranına taşınacak satır. Uygulamanızda bir ayarlar ekranı
/// oluşturduğunuzda bunu oraya taşıyın — ama silmeyin.
class PrivacyOptionsTile extends StatelessWidget {
  const PrivacyOptionsTile({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AdService.instance.privacyOptionsRequired,
      builder: (context, required, _) {
        if (!required) return const SizedBox.shrink();
        return Card(
          child: ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Reklam gizlilik seçenekleri'),
            onTap: AdService.instance.showPrivacyOptions,
          ),
        );
      },
    );
  }
}
