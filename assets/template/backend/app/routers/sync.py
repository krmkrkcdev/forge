"""Çevrimdışı öncelikli senkron uçları.

  * POST /sync/push : istemcinin yerel değişikliklerini gönderir. Sunucu
    kaydı `updated_at`'e göre son-yazan-kazanır ile birleştirir.
  * GET  /sync/pull : `since`'ten sonra değişen kayıtları (mezar taşları
    dahil) döndürür; istemci kendi kopyasını buna göre günceller.

Bu, tam bir senkron motoru DEĞİL — bilinçli olarak çekirdek iskelet. Çakışma
çözümü basit (son-yazan-kazanır); sürüm/vektör saat gerekiyorsa buradan
büyütülür.
"""

from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, Depends, Query
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..db import get_session
from ..models import Item as ItemModel
from ..schemas import Item as ItemSchema
from ..schemas import PushResult

router = APIRouter(prefix="/sync", tags=["sync"])


def _as_utc(dt: datetime) -> datetime:
    """Zaman damgasını karşılaştırılabilir kılar.

    Postgres TIMESTAMPTZ dilimli (aware) değer döndürür; SQLite dilimsiz
    (naive). İkisini karşılaştırmak TypeError verir. Bu yüzden dilimsiz
    değerleri UTC varsayıp herkesi UTC'ye çekiyoruz — böylece senkron mantığı
    hangi veritabanında olursa olsun aynı çalışır.
    """
    if dt.tzinfo is None:
        return dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


@router.post("/push", response_model=PushResult)
async def push(
    items: list[ItemSchema],
    session: AsyncSession = Depends(get_session),
) -> PushResult:
    accepted = 0
    for incoming in items:
        existing = await session.get(ItemModel, incoming.id)
        if existing is None:
            session.add(ItemModel(**incoming.model_dump()))
            accepted += 1
        elif _as_utc(incoming.updated_at) >= _as_utc(existing.updated_at):
            # Son-yazan-kazanır: gelen daha yeni (ya da eşit) ise uygula.
            existing.title = incoming.title
            existing.body = incoming.body
            existing.updated_at = incoming.updated_at
            existing.deleted = incoming.deleted
            accepted += 1
        # aksi halde sunucudaki daha yeni — gelen yok sayılır.
    await session.commit()
    return PushResult(accepted=accepted, server_time=datetime.now(timezone.utc))


@router.get("/pull", response_model=list[ItemSchema])
async def pull(
    since: Optional[datetime] = Query(default=None),
    session: AsyncSession = Depends(get_session),
) -> list[ItemModel]:
    stmt = select(ItemModel)
    if since is not None:
        stmt = stmt.where(ItemModel.updated_at > since)
    stmt = stmt.order_by(ItemModel.updated_at)
    rows = (await session.execute(stmt)).scalars().all()
    return list(rows)
