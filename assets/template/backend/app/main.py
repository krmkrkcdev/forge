"""{{APP_NAME}} — FastAPI uygulaması.

Çevrimdışı öncelikli mimaride sunucu bir YEDEK ve SENKRON katmanıdır; ana
kaynak telefondaki veritabanıdır. Bu yüzden uçlar bilinçli olarak sadedir:
sağlık ve senkron.
"""

from fastapi import FastAPI

from .routers import health, media, sync

app = FastAPI(title="{{APP_NAME}} API", version="0.1.0")

app.include_router(health.router)
app.include_router(sync.router)
app.include_router(media.router)
