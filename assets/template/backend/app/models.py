"""ORM modelleri.

Çevrimdışı öncelikli senkron için üç kural bu modelde somutlaşır:
  * Kimlik İSTEMCİDE üretilir (String PK) — kayıt internet yokken oluşturulup
    sonra çakışmasız senkronlanabilsin.
  * `updated_at` son-yazan-kazanır çözümü için taşınır.
  * `deleted` bir mezar taşıdır — silme de senkronlanabilsin diye satır
    fiziksel olarak silinmez, işaretlenir.
"""

from datetime import datetime

from sqlalchemy import Boolean, DateTime, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from .db import Base


class Item(Base):
    __tablename__ = "items"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    title: Mapped[str] = mapped_column(String(255), default="")
    body: Mapped[str] = mapped_column(Text, default="")
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    deleted: Mapped[bool] = mapped_column(Boolean, default=False)


class Media(Base):
    """Yüklenen bir fotoğrafın ÜST VERİSİ. Dosyanın kendisi diskte (MEDIA_DIR)
    durur; burada sadece kaydı tutulur. Kimlik istemcide üretilebilir —
    çevrimdışı çekilen fotoğraf, yüklenince aynı id'yle eşleşsin."""

    __tablename__ = "media"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    filename: Mapped[str] = mapped_column(String(255), default="")
    content_type: Mapped[str] = mapped_column(
        String(128), default="application/octet-stream"
    )
    size: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    deleted: Mapped[bool] = mapped_column(Boolean, default=False)
