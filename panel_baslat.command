#!/bin/bash
# Çift tıkla: çalışan paneli (dashboard/serve.dart) durdurur ve kaynaktan
# yeniden başlatır. handlers.dart değişince gerekir; web dosyaları diskten
# okunduğu için sayfa yenilemek yetmez, süreç yenilenmeli.
cd "$(dirname "$0")"
# Homebrew SONA eklenir: başa konursa Homebrew Ruby, chruby'nin seçtiği Ruby'yi
# gölgeler ve deploy.sh içindeki "bundle exec fastlane" çöker (yaşandı).
export PATH="$PATH:$HOME/development/flutter/bin:$HOME/flutter/bin:/opt/homebrew/bin:/usr/local/bin"
{
  echo "=== $(date) ==="
  # `dart run` başlatıcısı ile altındaki VM ayrı süreçler; portu tutan
  # hangisiyse o kapatılır, port boşalana kadar beklenir.
  for i in 1 2 3 4 5; do
    eski=$( (pgrep -f "dashboard/serve.dart"; lsof -ti :4577) 2>/dev/null | sort -u | tr '\n' ' ')
    [ -z "$eski" ] && break
    echo "→ eski panel süreci durduruluyor: $eski"
    kill $eski 2>/dev/null; sleep 2
  done
  if lsof -ti :4577 >/dev/null 2>&1; then
    echo "→ port hâlâ meşgul, zorla kapatılıyor"; kill -9 $(lsof -ti :4577) 2>/dev/null; sleep 1
  fi
  echo "→ dart pub get"; dart pub get 2>&1 | tail -2
  echo "→ dart analyze dashboard"; dart analyze dashboard 2>&1 | tail -15
  echo "→ panel başlatılıyor (http://localhost:4577)"
  exec dart run dashboard/serve.dart
} 2>&1 | tee panel.log
