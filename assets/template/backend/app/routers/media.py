"""Fotoğraf (medya) uçları — yükle, statik sakla, çek.

Dosyalar diskte MEDIA_DIR altında `<id>` adıyla durur (Docker'da kalıcı bir
volume'a bağlanır); üst verileri veritabanında. Kimlik istemcide üretilebilir:
çevrimdışı çekilen bir fotoğraf yerelde bir id alır, internet gelince aynı
id'yle yüklenir — çift kayıt olmaz.

  * POST   /media          : çok parçalı dosya yükler (image/*), üst veriyi döner
  * GET    /media          : üst verileri listeler
  * GET    /media/{id}     : dosyayı statik olarak çeker (FileResponse)
  * DELETE /media/{id}     : mezar taşıyla siler ve diskten kaldırır
"""

import os
import uuid
from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from fastapi.responses import FileResponse
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..db import get_session
from ..models import Media as MediaModel
from ..schemas import Media as MediaSchema

router = APIRouter(prefix="/media", tags=["media"])

# Docker'da bir volume buraya bağlanır (bkz. docker-compose.yml). Yerelde
# çalıştırırken MEDIA_DIR ile değiştirilebilir.
MEDIA_DIR = os.environ.get("MEDIA_DIR", "/srv/media")
MAX_BYTES = 10 * 1024 * 1024  # 10 MB
ALLOWED_TYPES = {"image/jpeg", "image/png", "image/webp", "image/gif"}


def _path(media_id: str) -> str:
    # basename: dizin geçişini (../) engeller.
    return os.path.join(MEDIA_DIR, os.path.basename(media_id))


@router.post("", response_model=MediaSchema)
async def upload(
    file: UploadFile = File(...),
    id: Optional[str] = Form(default=None),
    session: AsyncSession = Depends(get_session),
) -> MediaModel:
    if file.content_type not in ALLOWED_TYPES:
        raise HTTPException(415, f"Desteklenmeyen tür: {file.content_type}")

    data = await file.read()
    if len(data) > MAX_BYTES:
        raise HTTPException(413, "Dosya çok büyük (en fazla 10 MB).")

    media_id = id or uuid.uuid4().hex
    os.makedirs(MEDIA_DIR, exist_ok=True)
    with open(_path(media_id), "wb") as f:
        f.write(data)

    row = await session.get(MediaModel, media_id)
    now = datetime.now(timezone.utc)
    if row is None:
        row = MediaModel(
            id=media_id,
            filename=file.filename or media_id,
            content_type=file.content_type,
            size=len(data),
            created_at=now,
            deleted=False,
        )
        session.add(row)
    else:
        row.filename = file.filename or row.filename
        row.content_type = file.content_type
        row.size = len(data)
        row.deleted = False
    await session.commit()
    await session.refresh(row)
    return row


@router.get("", response_model=list[MediaSchema])
async def listing(session: AsyncSession = Depends(get_session)) -> list[MediaModel]:
    stmt = (
        select(MediaModel)
        .where(MediaModel.deleted.is_(False))
        .order_by(MediaModel.created_at)
    )
    return list((await session.execute(stmt)).scalars().all())


@router.get("/{media_id}")
async def fetch(
    media_id: str,
    session: AsyncSession = Depends(get_session),
) -> FileResponse:
    row = await session.get(MediaModel, media_id)
    if row is None or row.deleted:
        raise HTTPException(404, "Fotoğraf bulunamadı.")
    path = _path(media_id)
    if not os.path.exists(path):
        raise HTTPException(404, "Dosya diskte yok.")
    return FileResponse(path, media_type=row.content_type, filename=row.filename)


@router.delete("/{media_id}", response_model=MediaSchema)
async def delete(
    media_id: str,
    session: AsyncSession = Depends(get_session),
) -> MediaModel:
    row = await session.get(MediaModel, media_id)
    if row is None:
        raise HTTPException(404, "Fotoğraf bulunamadı.")
    row.deleted = True  # mezar taşı — senkron için satır silinmez, işaretlenir.
    await session.commit()
    path = _path(media_id)
    if os.path.exists(path):
        os.remove(path)
    await session.refresh(row)
    return row
