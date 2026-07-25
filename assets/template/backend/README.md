# {{APP_NAME}} — Backend

FastAPI + PostgreSQL. Çevrimdışı öncelikli mimaride sunucu bir **yedek ve
senkron katmanı**dır; ana kaynak telefondaki veritabanıdır.

## Çalıştır (docker)

```bash
cd backend
docker compose up --build
```

- API: http://localhost:8000
- Sağlık: http://localhost:8000/health
- Otomatik dokümanlar: http://localhost:8000/docs

`docker compose up` önce Postgres'i hazırlar, göçleri (`alembic upgrade head`)
uygular ve sunucuyu başlatır.

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
