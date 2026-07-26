# {{APP_NAME}} — Backend

FastAPI + PostgreSQL. Çevrimdışı öncelikli mimaride sunucu bir **yedek ve
senkron katmanı**dır; ana kaynak telefondaki veritabanıdır.

## Çalıştır (docker)

```bash
cd backend
cp .env.example .env

# Zorunlu sırrı üretin ve .env içine yazın — YALNIZCA BİR KEZ:
openssl rand -base64 24   # POSTGRES_PASSWORD

docker compose up -d --build
curl 127.0.0.1:8000/health     # {"status":"ok"}
```

`docker compose up` önce Postgres'i hazırlar, göçleri (`alembic upgrade head`)
uygular ve sunucuyu başlatır. API yalnızca `127.0.0.1` üzerinden dinler;
dışarıya açılması ters vekil ile yapılır. Otomatik dokümanlar:
http://127.0.0.1:8000/docs

> `POSTGRES_PASSWORD`'u yığın bir kez ayağa kalktıktan sonra değiştirmeyin.
> Postgres ilk kurulumdaki parolayı veri dizinine yazar; sonradan değişen
> değer yok sayılır ve API "password authentication failed" ile restart
> döngüsüne girer. Gerçekten gerekiyorsa veritabanını sıfırlayın:
> `docker compose down -v && docker compose up -d --build`

## Sunucuya kurulum

Paneldeki **Sunucuya kur** düğmesi SSH ile bağlanır, `/opt/services/<proje>`
klasörüne depoyu klonlar (varsa `git pull` ile günceller), `.env` yoksa
üretir ve `docker compose up -d --build` çalıştırır. Kodu **git'ten** alır —
commit'lenmemiş ya da push'lanmamış iş varsa hiç başlamaz.

Kurulumdan sonra ters vekilde (Nginx Proxy Manager) bir Proxy Host eklenir:

| Alan | Değer |
|---|---|
| Domain Names | `{{PROJECT_NAME}}.ornek.com` |
| Forward Hostname | `{{PROJECT_NAME}}-api` |
| Forward Port | `8000` |
| SSL | Request a new SSL Certificate + Force SSL |

Forward Port konteyner içi porttur (`8000`); `.env` içindeki `API_PORT`
yalnızca sunucunun kendi içinden test içindir, vekil onu görmez.

## Uçlar

| Uç | İş |
|---|---|
| `GET /health` | Sağlık — dağıtım ve testler bunu yoklar |
| `POST /sync/push` | İstemcinin yerel değişikliklerini gönderir (son-yazan-kazanır) |
| `GET /sync/pull?since=<iso>` | `since`'ten sonra değişenleri döndürür (silmeler dahil) |
| `POST /media` | Fotoğraf yükler (çok parçalı, `image/*`); üst veriyi döner |
| `GET /media` | Yüklü fotoğrafların üst verisini listeler |
| `GET /media/{id}` | Fotoğrafı statik olarak çeker |
| `DELETE /media/{id}` | Fotoğrafı siler (mezar taşı + diskten kaldırır) |

### Fotoğraflar

Dosyalar diskte `MEDIA_DIR` (docker'da kalıcı `media` volume'u) altında durur;
üst verileri veritabanında. Kimlik istemcide verilebilir (`id` form alanı) —
çevrimdışı çekilen fotoğraf, internet gelince aynı id'yle yüklenir.

```bash
# yükle
curl -F "file=@foto.jpg" -F "id=foto1" http://localhost:8000/media
# çek
curl http://localhost:8000/media/foto1 -o indirilen.jpg
```

Sınırlar: `image/jpeg|png|webp|gif`, en fazla 10 MB (`app/routers/media.py`'de
ayarlanır). Ölçek büyüdüğünde diski nesne depolamayla (S3/MinIO) değiştirmek
`media.py`'deki yükle/çek fonksiyonlarını değiştirmekle sınırlıdır.

## Test

Docker gerekmez — bellek içi SQLite ile çalışır:

```bash
cd backend
pip install -r requirements-dev.txt
pytest
```

App tarafındaki sözleşme testi çalışan sunucuya bakar:

```bash
cd backend && docker compose up -d
cd ../app && flutter test test/api_contract_test.dart \
  --dart-define=CONTRACT_API_URL=http://127.0.0.1:8000
```

## Büyütme

Bu çekirdek iskelettir. Sık ihtiyaçlar ve nereye eklenir:

- **Yeni kaynak:** `app/models.py` + `app/schemas.py` + `app/routers/`'a bir
  yönlendirici; `alembic revision` ile göç.
- **Kimlik doğrulama:** `app/main.py`'da bir bağımlılık (API anahtarı / token).
- **Gelişmiş çakışma çözümü:** `sync.py`'daki son-yazan-kazanır yerine sürüm
  veya vektör saat.
