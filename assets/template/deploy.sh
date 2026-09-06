#!/usr/bin/env bash
set -euo pipefail

# ============================================================
#  Flutter Hızlı Yayınlama Aracı
#
#  Kullanım:
#    ./deploy.sh ios beta        -> TestFlight'a yükle
#    ./deploy.sh ios release     -> App Store'a yükle + incelemeye gönder
#    ./deploy.sh android beta    -> Play Store Beta kanalına yükle
#    ./deploy.sh android release -> Play Store Production'a yükle
#    ./deploy.sh all beta        -> İkisini birden (beta)
#    ./deploy.sh all release     -> İkisini birden (release)
#
#  Ek bayraklar:
#    --dry-run       Build alır, mağazaya YÜKLEMEZ (deneme çalıştırması)
#    --no-bump       Build numarasını artırmaz (başarısız denemeyi tekrarlarken)
#    --skip-clean    flutter clean adımını atlar (hızlı tekrar build)
# ============================================================

PLATFORM=""
LANE="beta"
DRY_RUN=false
NO_BUMP=false
SKIP_CLEAN=false
SKIP_CHECKS=false

usage() {
  echo "Kullanım: ./deploy.sh [ios|android|all] [beta|release] [bayraklar]"
  echo "Bayraklar: --dry-run --no-bump --skip-clean --skip-checks"
  echo "           --notes=\"Sürüm notu\"   testçilere gösterilecek metin"
  echo ""
  echo "Örnek:  ./deploy.sh ios beta --notes=\"Saat seçimi eklendi\""
}

# ---------- Argümanları ayrıştır ----------
POSITIONAL=()
for arg in "$@"; do
  case $arg in
    --dry-run)     DRY_RUN=true ;;
    --no-bump)     NO_BUMP=true ;;
    --skip-clean)  SKIP_CLEAN=true ;;
    --skip-checks) SKIP_CHECKS=true ;;
    --notes=*)     RELEASE_NOTES="${arg#*=}" ;;
    -h|--help)     usage; exit 0 ;;
    -*)            echo "❌ Bilinmeyen bayrak: $arg"; usage; exit 1 ;;
    *)             POSITIONAL+=("$arg") ;;
  esac
done

PLATFORM="${POSITIONAL[0]:-}"
LANE="${POSITIONAL[1]:-beta}"

if [ -z "$PLATFORM" ]; then usage; exit 1; fi

case "$PLATFORM" in
  ios|android|all) ;;
  *) echo "❌ Geçersiz platform: $PLATFORM (ios | android | all olmalı)"; exit 1 ;;
esac

case "$LANE" in
  beta|release) ;;
  *) echo "❌ Geçersiz lane: $LANE (beta | release olmalı)"; exit 1 ;;
esac

# Script'i her zaman proje kökünden çalıştır
cd "$(dirname "$0")"

if [ ! -f pubspec.yaml ]; then
  echo "❌ pubspec.yaml bulunamadı. Bu script Flutter projesinin kök dizininde olmalı."
  exit 1
fi

# ---------- .env yükle ----------
if [ ! -f .env ]; then
  echo "❌ .env dosyası bulunamadı. Önce: cp .env.example .env"
  exit 1
fi
# 'set -a' ile source: boşluk ve tırnak içeren değerler de doğru okunur.
set -a
# shellcheck disable=SC1091
source ./.env
set +a

# ---------- Gerekli değişkenleri doğrula ----------
require_env() {
  local missing=()
  for var in "$@"; do
    if [ -z "${!var:-}" ]; then missing+=("$var"); fi
  done
  if [ ${#missing[@]} -gt 0 ]; then
    echo "❌ .env dosyasında eksik değişken(ler): ${missing[*]}"
    exit 1
  fi
}

require_file() {
  if [ ! -f "$1" ]; then
    echo "❌ Dosya bulunamadı: $1  ($2)"
    exit 1
  fi
}

if [ "$PLATFORM" = "ios" ] || [ "$PLATFORM" = "all" ]; then
  require_env ASC_KEY_ID ASC_ISSUER_ID ASC_KEY_FILEPATH APPLE_TEAM_ID APP_IDENTIFIER
  require_file "$ASC_KEY_FILEPATH" "App Store Connect API anahtarı (.p8)"

  # fastlane ios/ klasörü içinden çalıştırılır (aşağıda `cd ios`), bu yüzden
  # .env'deki proje köküne göre yazılmış göreli yol orada çözülemez.
  # Mutlaklaştırıp export ediyoruz ki .env okunaklı kalsın.
  case "$ASC_KEY_FILEPATH" in
    /*) ;;
    # $PWD degil $(pwd -P): launchd altindan gelen surecte PWD "." gibi
    # bozuk bir degerle miras kalabiliyor ve bash bunu gecerli sayiyor —
    # sonuc yine goreli bir yol oluyor, fastlane ios/ icinden bulamiyor.
    *) ASC_KEY_FILEPATH="$(pwd -P)/${ASC_KEY_FILEPATH#./}" ;;
  esac
  export ASC_KEY_FILEPATH

  # Bu anahtar yoksa App Store Connect her yüklemede "ihracat uyumluluğu"
  # sorusunu elle yanıtlamanızı bekler ve otomatik akış orada durur.
  if ! grep -q "ITSAppUsesNonExemptEncryption" ios/Runner/Info.plist 2>/dev/null; then
    echo "❌ ios/Runner/Info.plist içinde ITSAppUsesNonExemptEncryption yok."
    echo "   Bu anahtar olmadan her yüklemede App Store Connect'te ihracat"
    echo "   uyumluluğu sorusunu elle yanıtlamanız gerekir."
    echo "   Uygulama özel şifreleme kullanmıyorsa Info.plist'e ekleyin:"
    echo "     <key>ITSAppUsesNonExemptEncryption</key><false/>"
    exit 1
  fi
fi
if [ "$PLATFORM" = "android" ] || [ "$PLATFORM" = "all" ]; then
  require_env GOOGLE_PLAY_JSON_KEY ANDROID_PACKAGE_NAME
  require_file "$GOOGLE_PLAY_JSON_KEY" "Google Play service account JSON"

  # iOS tarafındaki ile aynı sebep: fastlane android/ içinden çalışır.
  case "$GOOGLE_PLAY_JSON_KEY" in
    /*) ;;
    # iOS tarafindaki ile ayni sebep: $PWD'ye guvenme (bkz. yukarisi).
    *) GOOGLE_PLAY_JSON_KEY="$(pwd -P)/${GOOGLE_PLAY_JSON_KEY#./}" ;;
  esac
  export GOOGLE_PLAY_JSON_KEY

  # Debug anahtarıyla imzalanmış paketi Play Console reddeder. Bunu build ve
  # yükleme turunu harcamadan önce yakalarız.
  if [ ! -f android/key.properties ]; then
    echo "❌ android/key.properties bulunamadı."
    echo "   Sürüm derlemesi debug anahtarıyla imzalanır ve Play Store bu"
    echo "   paketi kabul etmez. Kurulum: android/key.properties.example"
    exit 1
  fi
fi

# ---------- Ruby / bundler ön kontrolü ----------
# Fastlane "bundle exec" ile çalışır ve bu makinede birden fazla Ruby var
# (chruby'nin ~/.rubies'i, Homebrew'un ruby'si, sistem Ruby'si). Tuzak şu:
# kabuk profili chruby ile GEM_HOME'u Ruby 3.2'ye ayarlar, ama PATH'in başına
# sonradan /opt/homebrew/bin girer. `bundle` artık Homebrew'un Ruby 4'üyle
# çalışır, Ruby 3.2 için kurulmuş gem'leri yüklemeye kalkar ve çöker.
# Yaşandı (2026-09, bubble_2048 ilk TestFlight): "bundle exec fastlane
# çalıştırılamadı". Çözüm: ruby, gem ve bundle'ı TEK ve aynı Ruby'den kullan,
# gem'ler eksikse (yeni proje, Gemfile.lock yok) kur, hata olursa tahmin
# değil gerçek çıktıyı göster. Hepsi build harcamadan, saniyeler içinde.
ruby_ortami_hazirla() {
  local chruby_sh=/opt/homebrew/opt/chruby/share/chruby/chruby.sh
  if [ -n "${RUBY_ROOT:-}" ] && [ -x "$RUBY_ROOT/bin/ruby" ]; then
    # 1) chruby bu kabukta zaten aktif: seçtiği Ruby'yi PATH'in BAŞINA al ki
    #    sonradan öne geçen /opt/homebrew/bin onu gölgelemesin.
    export PATH="${GEM_HOME:+$GEM_HOME/bin:}$RUBY_ROOT/bin:$PATH"
  elif [ -f "$chruby_sh" ] && [ -d "$HOME/.rubies" ]; then
    # 2) chruby kurulu ama yüklenmemiş (panel launchd'den ya da profil
    #    okunmadan başlatıldığında olur): yükle, .ruby-version varsa onu,
    #    yoksa kurulu en yeni Ruby'yi seç.
    set +u
    # shellcheck disable=SC1090
    . "$chruby_sh"
    if [ -f .ruby-version ]; then
      chruby "$(cat .ruby-version)" || true
    else
      chruby "$(ls "$HOME/.rubies" | tail -1)" || true
    fi
    set -u
    if [ -n "${RUBY_ROOT:-}" ]; then
      export PATH="${GEM_HOME:+$GEM_HOME/bin:}$RUBY_ROOT/bin:$PATH"
    fi
  else
    # 3) Sürüm yöneticisi yok: başka bir Ruby'den miras kalmış GEM_*
    #    değişkenleri temizle, PATH'teki ilk Ruby kendi gem'lerini kullansın.
    unset GEM_HOME GEM_PATH GEM_ROOT
  fi
}
ruby_ortami_hazirla
echo "💎 Ruby: $(ruby -v 2>/dev/null | cut -d' ' -f1-2 || echo bulunamadı) · bundle: $(command -v bundle || echo bulunamadı)"

if ! command -v bundle >/dev/null 2>&1; then
  echo "❌ 'bundle' bulunamadı. Ruby kurulumunu kontrol edin (brew install chruby ruby-install)."
  exit 1
fi

# Gem'ler eksikse ya da Gemfile.lock hiç yoksa (yeni proje) kur. Bu, ilk
# yayında "bundle install'ı unuttum" hatasını kökten kaldırır.
if ! bundle check >/dev/null 2>&1; then
  echo "💎 Gem'ler eksik ya da Gemfile.lock yok; 'bundle install' çalıştırılıyor..."
  if ! bundle install; then
    echo "❌ bundle install başarısız. Yukarıdaki çıktıya bakın."
    exit 1
  fi
fi

if ! fl_surum=$(bundle exec fastlane --version 2>&1); then
  echo "❌ 'bundle exec fastlane' çalıştırılamadı. Son satırlar:"
  echo "$fl_surum" | tail -15 | sed 's/^/   /'
  echo "   ruby: $(command -v ruby) · bundle: $(command -v bundle) · GEM_HOME=${GEM_HOME:-boş}"
  echo "   Çare genellikle: bu üçü aynı Ruby'den olmalı. Terminalde 'chruby' ile"
  echo "   Ruby seçip 'bundle install' çalıştırın, sonra yeniden deneyin."
  exit 1
fi
echo "💎 $(echo "$fl_surum" | grep -o 'fastlane [0-9][0-9.]*' | tail -1 || echo fastlane hazır)"

# Fastlane'in dry-run modunu görmesi için dışa aktar
export DEPLOY_DRY_RUN="$DRY_RUN"
export DEPLOY_LANE="$LANE"
# --notes ile verilen metin. Boşsa fastlane release_notes.txt dosyasına,
# o da yoksa varsayılan metne düşer.
export DEPLOY_RELEASE_NOTES="${RELEASE_NOTES:-}"

# Reklam birimi kimlikleri koda --dart-define ile gecer. .env'de tanimli
# degilse kod Google'in TEST kimliklerine duser: gercek kimliklerle
# gelistirme yapip kendi reklamina tiklamak AdMob hesabini kapattirir.
DART_DEFINES=()
[ -n "${ADMOB_BANNER_IOS:-}" ] && DART_DEFINES+=(--dart-define=ADMOB_BANNER_IOS="$ADMOB_BANNER_IOS")
[ -n "${ADMOB_INTERSTITIAL_IOS:-}" ] && DART_DEFINES+=(--dart-define=ADMOB_INTERSTITIAL_IOS="$ADMOB_INTERSTITIAL_IOS")
[ -n "${ADMOB_BANNER_ANDROID:-}" ] && DART_DEFINES+=(--dart-define=ADMOB_BANNER_ANDROID="$ADMOB_BANNER_ANDROID")
[ -n "${ADMOB_INTERSTITIAL_ANDROID:-}" ] && DART_DEFINES+=(--dart-define=ADMOB_INTERSTITIAL_ANDROID="$ADMOB_INTERSTITIAL_ANDROID")
[ -n "${API_BASE_URL:-}" ] && DART_DEFINES+=(--dart-define=API_BASE_URL="$API_BASE_URL")

if [ ${#DART_DEFINES[@]} -gt 0 ]; then
  echo "🎯 ${#DART_DEFINES[@]} adet --dart-define uygulanacak."
else
  echo "ℹ️  --dart-define verilmedi; kod içindeki varsayılanlar kullanılacak."
fi

# Not: aşağıda diziyi ${DART_DEFINES[@]+"..."} biçiminde genişletiyoruz.
# macOS'un bash 3.2'sinde `set -u` altında BOŞ bir dizinin doğrudan
# "${arr[@]}" ile genişletilmesi "unbound variable" hatası verir.

# Mağaza hazırlık denetimi. forge kurulu değilse sessizce atlanır — bu betik
# forge'a bağımlı olmamalı. Engel bulunursa yayın başlamadan durur; amaç tam
# bir derleme ve yükleme turunu harcamadan önce hatayı görmek.
#
# Üretim yayınında uyarılar da engel sayılır (--strict). Beta'da sayılmaz:
# TestFlight'a eksik ikonla ya da test reklam kimliğiyle çıkmak meşrudur,
# mağazaya çıkmak değildir. "Sonra hallederim" diyerek yayınlanan uyarı,
# bir daha hiç ele alınmıyor.
if [ "$SKIP_CHECKS" != true ] && command -v forge >/dev/null 2>&1; then
  DOCTOR_ARGS=(--path .)
  [ "$LANE" = "release" ] && DOCTOR_ARGS+=(--strict)
  echo "🔎 forge doctor çalıştırılıyor..."
  if ! forge doctor "${DOCTOR_ARGS[@]}"; then
    echo ""
    echo "❌ Yayın durduruldu: yukarıdaki engelleri giderin."
    echo "   Denetimi atlamak için: --skip-checks"
    exit 1
  fi
fi

# Statik analiz. forge doctor mağaza hazırlığına bakar, koda bakmaz; analiz
# hatası olan proje build adımında ama DAKİKALAR sonra, temizlik ve derleme
# harcandıktan sonra patlar. Burada saniyeler içinde yakalanır.
#
# Yalnızca üretim yayınında zorunlu: beta'da hızlı tur atmak meşrudur.
if [ "$SKIP_CHECKS" != true ] && [ "$LANE" = "release" ]; then
  echo "🧪 flutter analyze çalıştırılıyor..."
  if ! flutter analyze; then
    echo ""
    echo "❌ Yayın durduruldu: analiz bulguları var."
    echo "   Denetimi atlamak için: --skip-checks"
    exit 1
  fi
fi

if [ "$DRY_RUN" = true ]; then
  echo "🧪 DRY-RUN: build alınacak, mağazaya yükleme YAPILMAYACAK."
fi

# ---------- Hata durumunda pubspec.yaml'ı geri al ----------
PUBSPEC_BACKUP=""
restore_pubspec() {
  local code=$?
  if [ $code -ne 0 ] && [ -n "$PUBSPEC_BACKUP" ] && [ -f "$PUBSPEC_BACKUP" ]; then
    mv -f "$PUBSPEC_BACKUP" pubspec.yaml
    echo ""
    echo "↩️  Hata oluştu — pubspec.yaml eski build numarasına geri alındı."
  elif [ -n "$PUBSPEC_BACKUP" ]; then
    rm -f "$PUBSPEC_BACKUP"
  fi
  exit $code
}
trap restore_pubspec EXIT

# ---------- Build numarasını artır ----------
VERSION_LINE=$(grep -E '^version:[[:space:]]*' pubspec.yaml | head -n1 || true)
if [ -z "$VERSION_LINE" ]; then
  echo "❌ pubspec.yaml içinde 'version:' satırı bulunamadı."
  exit 1
fi

VERSION_VALUE=$(echo "$VERSION_LINE" | sed -E 's/^version:[[:space:]]*//; s/[[:space:]]*(#.*)?$//')
VERSION_NAME="${VERSION_VALUE%%+*}"

if [[ "$VERSION_VALUE" != *"+"* ]]; then
  echo "❌ pubspec.yaml versiyonu build numarası içermiyor: '$VERSION_VALUE'"
  echo "   Beklenen biçim: version: 1.0.0+1"
  exit 1
fi

CURRENT_BUILD="${VERSION_VALUE##*+}"
if ! [[ "$CURRENT_BUILD" =~ ^[0-9]+$ ]]; then
  echo "❌ Build numarası sayısal değil: '$CURRENT_BUILD' (version: $VERSION_VALUE)"
  exit 1
fi

if [ "$NO_BUMP" = true ]; then
  NEW_BUILD="$CURRENT_BUILD"
  echo "⏭️  Build numarası artırılmadı: $VERSION_NAME+$NEW_BUILD"
else
  NEW_BUILD=$((CURRENT_BUILD + 1))
  PUBSPEC_BACKUP="$(mktemp)"
  cp pubspec.yaml "$PUBSPEC_BACKUP"
  # Sadece 'version:' ile başlayan satırı, sadece ilk eşleşmede değiştir.
  awk -v new="version: ${VERSION_NAME}+${NEW_BUILD}" '
    !done && /^version:[[:space:]]*/ { print new; done=1; next } { print }
  ' pubspec.yaml > pubspec.yaml.tmp && mv pubspec.yaml.tmp pubspec.yaml
  echo "🔼 Build numarası: $CURRENT_BUILD → $NEW_BUILD  (sürüm: $VERSION_NAME+$NEW_BUILD)"
fi

export DEPLOY_VERSION_NAME="$VERSION_NAME"
export DEPLOY_BUILD_NUMBER="$NEW_BUILD"

# ---------- Flutter hazırlığı ----------
if [ "$SKIP_CLEAN" = true ]; then
  echo "⏭️  flutter clean atlandı."
else
  echo "🔧 Flutter bağımlılıkları hazırlanıyor..."
  flutter clean
fi
flutter pub get

# ---------- Kalite kapısı ----------
# Mağazaya gönderilen bir sürüm geri alınamaz; analiz ve testler burada
# çalışmazsa bozuk bir build kullanıcılara ulaşabilir. Bilinçli olarak
# yükleme adımından ÖNCE, build'den önce çalışır: hızlı başarısız olur.
if [ "$SKIP_CHECKS" = true ]; then
  echo "⏭️  Kalite kontrolleri atlandı (--skip-checks)."
else
  echo "🔍 flutter analyze..."
  if ! flutter analyze; then
    echo ""
    echo "❌ Analiz hataları var. Düzeltin ya da bilinçli olarak atlamak için:"
    echo "   ./deploy.sh $PLATFORM $LANE --skip-checks"
    exit 1
  fi

  # İçinde gerçekten test dosyası yoksa test adımı atlanır: `flutter test`
  # boş test dizininde 1 koduyla çıkar ve yayın sebepsiz yere dururdu.
  if [ -n "$(find test -name '*_test.dart' -print -quit 2>/dev/null)" ]; then
    echo "🧪 flutter test..."
    if ! flutter test; then
      echo ""
      echo "❌ Testler başarısız. Düzeltin ya da bilinçli olarak atlamak için:"
      echo "   ./deploy.sh $PLATFORM $LANE --skip-checks"
      exit 1
    fi
  fi
fi

deploy_ios() {
  if [[ "$OSTYPE" != darwin* ]]; then
    echo "❌ iOS build'i yalnızca macOS üzerinde alınabilir (Xcode gerekir)."
    exit 1
  fi

  echo ""
  echo "🍎 iOS: Dart derleniyor ve Xcode yapılandırması üretiliyor..."
  # Bu adım Generated.xcconfig'i (CURRENT_PROJECT_VERSION dahil) pubspec'e göre yazar.
  # İmzalama fastlane'e (gym) bırakılır.
  flutter build ios --release --no-codesign ${DART_DEFINES[@]+"${DART_DEFINES[@]}"}

  echo "🍎 iOS: Fastlane ile arşivleniyor ve yükleniyor (lane: $LANE)..."
  # clean: false — flutter build çıktısını yeniden derlememek için (bkz. ios/fastlane/Fastfile)
  (cd ios && bundle exec fastlane "$LANE")
}

deploy_android() {
  echo ""
  echo "🤖 Android: App Bundle build alınıyor..."
  flutter build appbundle --release ${DART_DEFINES[@]+"${DART_DEFINES[@]}"}

  echo "🤖 Android: Fastlane ile Play Store'a yükleniyor (lane: $LANE)..."
  (cd android && bundle exec fastlane "$LANE")
}

case $PLATFORM in
  ios)     deploy_ios ;;
  android) deploy_android ;;
  all)     deploy_ios; deploy_android ;;
esac

echo ""
if [ "$DRY_RUN" = true ]; then
  echo "✅ DRY-RUN tamamlandı — build başarılı, yükleme yapılmadı. ($PLATFORM / $LANE)"
else
  echo "✅ Tamamlandı! ($PLATFORM / $LANE / build $NEW_BUILD)"
  echo "   İpucu: sürümü işaretlemek için  git tag v$VERSION_NAME+$NEW_BUILD && git push --tags"
fi
