/// Bir denetim bulgusunun ciddiyeti.
enum Severity {
  /// Yayını tamamen engeller. Mağaza paketi reddeder ya da yükleme hiç başlamaz.
  blocker('ENGEL'),

  /// Yayın olur ama her seferinde elle müdahale gerektirir ya da red riski taşır.
  warning('UYARI'),

  /// İyileştirme önerisi.
  info('BİLGİ');

  const Severity(this.label);
  final String label;
}

/// Denetimin hangi aşamayı ilgilendirdiği.
enum Platform { ios, android, both }

class Finding {
  const Finding({
    required this.id,
    required this.severity,
    required this.platform,
    required this.title,
    required this.why,
    required this.fix,
    this.autoFixable = false,
  });

  /// Kısa, sabit kimlik. Bulguyu bastırmak veya betikten yakalamak için.
  final String id;

  final Severity severity;
  final Platform platform;

  /// Neyin yanlış olduğu, tek cümle.
  final String title;

  /// Neden önemli olduğu — bu olmadan kullanıcı bulguyu görmezden gelir.
  final String why;

  /// Nasıl düzeltileceği.
  final String fix;

  /// `forge fix` bunu kendisi düzeltebilir mi?
  final bool autoFixable;
}
