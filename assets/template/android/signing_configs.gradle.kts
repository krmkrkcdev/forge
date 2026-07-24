    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                // Debug anahtarıyla imzalanmış paketi Play Store kabul etmez.
                // Sessizce debug'a düşmek yerine, yerel denemeye izin verip
                // yükleme öncesi net biçimde uyarıyoruz.
                logger.warn(
                    "\n⚠️  android/key.properties bulunamadı — sürüm derlemesi DEBUG " +
                    "anahtarıyla imzalanıyor.\n" +
                    "   Bu paket Play Store'a YÜKLENEMEZ. Kurulum için: " +
                    "android/key.properties.example\n"
                )
                signingConfigs.getByName("debug")
            }
        }
    }
