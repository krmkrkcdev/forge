"""Veritabanı bağlantısı ve oturum (SQLAlchemy 2.0, async).

DATABASE_URL ortam değişkeninden okunur; docker-compose bunu Postgres'e
yönlendirir. Motor tembeldir — içe aktarma anında bağlantı açmaz, bu yüzden
testler Postgres olmadan da bu modülü içe aktarabilir.
"""

import os
from collections.abc import AsyncIterator

from sqlalchemy.ext.asyncio import (
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)
from sqlalchemy.orm import DeclarativeBase

DATABASE_URL = os.environ.get(
    "DATABASE_URL",
    "postgresql+asyncpg://postgres:postgres@db:5432/{{PROJECT_NAME}}",
)


class Base(DeclarativeBase):
    """Bütün ORM modellerinin ortak tabanı."""


engine = create_async_engine(DATABASE_URL, echo=False)
async_session = async_sessionmaker(engine, expire_on_commit=False)


async def get_session() -> AsyncIterator[AsyncSession]:
    """İstek başına bir veritabanı oturumu verir (FastAPI Depends ile)."""
    async with async_session() as session:
        yield session
