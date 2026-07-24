// Yayın imzalama bilgileri android/key.properties dosyasından okunur.
// Bu dosya ve anahtar deposu (.jks) git'e girmez; birlikte yedeklenmelidir —
// kaybedilirse uygulamanın güncellemeleri Play Store'a bir daha yüklenemez.
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
val keystoreProperties = Properties().apply {
    if (hasReleaseKeystore) {
        keystorePropertiesFile.inputStream().use { load(it) }
    }
}
