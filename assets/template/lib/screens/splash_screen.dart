import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'home_screen.dart';

/// Açılış ekranı: siyah zeminde PikeLabs logosu, altında yazı.
/// Bütün uygulamalarda AYNI dosya — forge şablonundan gelir; logo dosyası
/// assets/splash/pikelabs.png ile birlikte marka açılışını oluşturur.
///
/// [duration] kadar görünür ve ana sayfaya geçer. Süre dolmadan
/// dokunulursa da geçer — bir açılış ekranı kullanıcıyı asla bekletmemeli.
///
/// Logo marka dosyasının KENDİSİDİR: kırpılmaz, maskelenmez, rengiyle
/// oynanmaz. Görselin zemini zaten saf siyah olduğu için ekranın
/// zeminiyle birebir kaynaşıyor; bu yüzden efektler de görüntünün
/// üstüne boya sürerek değil, ışık ekleyerek yapılır.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  /// Logonun ekranda kaldığı süre (kullanıcı kararı).
  ///
  /// Koreografi oranlı yazıldığı için süreyi değiştirmek sıralamayı
  /// bozmaz: giriş, ışık dalgası ve yazı hep aynı yüzdelerde olur.
  static const duration = Duration(seconds: 4);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  bool _gecildi = false;

  /// Marka turkuazı: logonun boynuzundaki renk.
  static const _teal = Color(0xFF39D8E8);

  // Koreografi. Değerler oranlı; süre değişse bile sıralama bozulmaz.
  late final Animation<double> _giris = CurvedAnimation(
    parent: _c,
    curve: const Interval(0.0, 0.38, curve: Curves.easeOutCubic),
  );
  late final Animation<double> _isik = CurvedAnimation(
    parent: _c,
    curve: const Interval(0.20, 0.70, curve: Curves.easeInOut),
  );

  /// Yazı logoyla AYNI anda belirir.
  ///
  /// Önce sadece logo, sonra yazı gelsin diye ayrı aralıklara
  /// koymuştum; ekranda bu "iki ayrı açılış" gibi okunuyordu
  /// (kullanıcı: "direk logo ve yazı gelmeli"). Artık tek bir giriş
  /// var; yazının kendi hareketi (harf aralığının toplanması) canlılığı
  /// zaten veriyor.
  late final Animation<double> _yazi = CurvedAnimation(
    parent: _c,
    curve: const Interval(0.0, 0.42, curve: Curves.easeOut),
  );

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: SplashScreen.duration)
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) _gec();
      })
      ..forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _gec() {
    if (_gecildi || !mounted) return;
    _gecildi = true;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 420),
        pageBuilder: (_, _, _) => const HomeScreen(),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  /// Parlaklığı ölçekleyen renk süzgeci.
  ///
  /// Siyahı siyah bırakır (0 × k = 0), yalnızca aydınlık yüzeyleri
  /// güçlendirir — yani logonun metali ışık yakalamış gibi olur, zemin
  /// hiç kıpırdamaz. Maskeyle ışık şeridi geçirmeyi denemek bu görselde
  /// çalışmaz: görüntü saydam değil, dikdörtgen bir leke bırakırdı.
  static ColorFilter _parlaklik(double k) => ColorFilter.matrix(<double>[
    k, 0, 0, 0, 0, //
    0, k, 0, 0, 0, //
    0, 0, k, 0, 0, //
    0, 0, 0, 1, 0, //
  ]);

  @override
  Widget build(BuildContext context) {
    final ekran = MediaQuery.sizeOf(context);
    // Görselin kendi kenar boşlukları var (içerik karenin ~%63'ü), bu
    // yüzden geniş yerleştirilir; siyah kenarlar zeminle aynı olduğu
    // için görünmez.
    final logoW = math.min(ekran.width * 0.86, ekran.height * 0.52);

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _gec,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final t = _c.value;
            // Işık dalgası: gelip geçen tek bir parlama.
            final vurus = math.sin(_isik.value * math.pi);
            return Stack(
              fit: StackFit.expand,
              children: [
                // Arkada nefes alan turkuaz hale. Siyah bir ekranda logo
                // tek başına "yapıştırılmış" duruyor; hale onu ışık
                // kaynağı hâline getiriyor.
                CustomPaint(
                  painter: _HalePainter(
                    guc: _giris.value,
                    nabiz: math.sin(t * math.pi * 2.4),
                    renk: _teal,
                  ),
                ),

                // Yükselen parıltılar.
                CustomPaint(
                  painter: _PariltiPainter(t: t, renk: _teal),
                ),

                // LOGO TAM ORTADA. Yazı ve çizgi, logonun altına
                // taşmadan konumlanır; böylece logo ekranın merkezinden
                // kaymaz.
                Center(
                  child: SizedBox(
                    width: logoW,
                    height: logoW,
                    child: Opacity(
                      opacity: _giris.value,
                      child: Transform.scale(
                        // Girişte yaklaşır, sonra çok hafif nefes alır.
                        scale:
                            (0.88 + _giris.value * 0.12) +
                            math.sin(t * math.pi * 2) * 0.008,
                        child: ColorFiltered(
                          colorFilter: _parlaklik(1 + vurus * 0.42),
                          child: Image.asset(
                            'assets/splash/pikelabs.png',
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.medium,
                            errorBuilder: (_, _, _) => const SizedBox(),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // Yazı: logonun altında, ekranın alt üçte birinde.
                Align(
                  alignment: const Alignment(0, 0.62),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Harf aralığı geniş başlayıp daralınca yazı
                      // "toplanarak yerine oturuyor" gibi görünüyor.
                      Opacity(
                        opacity: _yazi.value,
                        child: Text(
                          'PikeLabs',
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w300,
                            letterSpacing: 15 - _yazi.value * 11.4,
                            color: const Color(0xFFEAF6FA),
                            shadows: [
                              Shadow(
                                color: _teal.withValues(
                                  alpha: 0.55 * _yazi.value,
                                ),
                                blurRadius: 20,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      // İnce ilerleme çizgisi: sürenin ne kadarının kaldığını
                      // gösterir, bekleyiş belirsiz kalmasın.
                      Opacity(
                        opacity: _yazi.value * 0.7,
                        child: SizedBox(
                          width: 96,
                          height: 2,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: FractionallySizedBox(
                              widthFactor: t,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: _teal.withValues(alpha: 0.9),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Logonun arkasındaki turkuaz hale.
class _HalePainter extends CustomPainter {
  const _HalePainter({
    required this.guc,
    required this.nabiz,
    required this.renk,
  });

  final double guc;
  final double nabiz;
  final Color renk;

  @override
  void paint(Canvas canvas, Size size) {
    if (guc <= 0) return;
    // Hale, logonun durduğu yerde: ekranın tam ortası.
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width * (0.46 + nabiz * 0.02) * guc;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          colors: [
            renk.withValues(alpha: 0.18 * guc),
            renk.withValues(alpha: 0.05 * guc),
            Colors.transparent,
          ],
          stops: const [0.0, 0.45, 1.0],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
  }

  @override
  bool shouldRepaint(covariant _HalePainter old) =>
      old.guc != guc || old.nabiz != nabiz;
}

/// Yukarı süzülen parıltılar.
class _PariltiPainter extends CustomPainter {
  const _PariltiPainter({required this.t, required this.renk});

  /// 0..1 arası açılış ilerlemesi.
  final double t;
  final Color renk;

  static const _adet = 18;

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < _adet; i++) {
      // Konum ve hız çekirdekten türetilir: her açılışta aynı desen,
      // ama düzenli bir dizi gibi görünmeyecek kadar dağınık.
      final s = i * 12.9898;
      final x = (math.sin(s) * 0.5 + 0.5) * size.width;
      final hiz = 0.55 + (math.sin(s * 2.1) * 0.5 + 0.5) * 0.8;
      final gecikme = (math.sin(s * 3.3) * 0.5 + 0.5) * 0.35;
      final k = ((t - gecikme) * hiz).clamp(0.0, 1.0);
      if (k <= 0) continue;

      final y = size.height * (0.82 - k * 0.5);
      final r = 1.0 + (math.sin(s * 5.7) * 0.5 + 0.5) * 1.8;
      // Belirip sönerler; sonuna doğru hepsi kaybolur.
      final alfa = math.sin(k * math.pi) * 0.5;
      canvas.drawCircle(
        Offset(x + math.sin(k * 6 + s) * 10, y),
        r,
        Paint()..color = renk.withValues(alpha: alfa),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PariltiPainter old) => old.t != t;
}
