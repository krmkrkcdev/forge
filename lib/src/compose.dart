/// docker-compose dosyalarını okumaya yarayan küçük yardımcılar.
///
/// Tam bir YAML ayrıştırıcısı bilinçli olarak kullanılmıyor: burada aranan
/// tek şey, kurulumun güvenli olup olmadığına karar verdiren birkaç alan.
library;

/// docker-compose.yml içindeki üst düzey `name:` (proje adı) alanını okur;
/// yoksa `null` döner.
///
/// Proje adı sabitlenmemişse Docker onu çalışma dizininin adından türetir.
/// Aynı sunucudaki iki proje de compose'unu `backend/` altında tutuyorsa
/// ikisi de "backend" projesi sayılır: ikinci yığın ilkinin konteynerlerini
/// "bu projede tanımlı değil" diyerek siler, veritabanını devralır ve
/// `backend-api` imajının üzerine yazar. Gerçekten yaşandı; bu yüzden
/// "Sunucuya kur" adı olmayan bir compose'la başlamaz.
///
/// Girintili `name:` satırları (volume/ağ adları) ve `container_name:`
/// bilinçli olarak eşleşmez — yanlış pozitif, kurulumun başka bir yığını
/// ezmesine izin verirdi.
String? composeProjectName(String yaml) {
  for (final raw in yaml.split('\n')) {
    final line = raw.trimRight();
    if (line.isEmpty || line.startsWith('#')) continue;
    if (!line.startsWith('name:')) continue;
    var value = line.substring('name:'.length).trim();
    final hash = value.indexOf('#');
    if (hash >= 0) value = value.substring(0, hash).trim();
    value = value.replaceAll('"', '').replaceAll("'", '').trim();
    if (value.isNotEmpty) return value;
  }
  return null;
}
