"""Paylaşılan test kurulumu.

Gerçek Postgres yerine bellek içi SQLite (StaticPool ile tek bağlantı) ve
geçici bir MEDIA_DIR kullanır; böylece testler docker olmadan çalışır. MEDIA_DIR
app içe aktarılmadan ÖNCE ayarlanmalı — bu yüzden en üstte.
"""

import os
import tempfile

os.environ.setdefault("MEDIA_DIR", tempfile.mkdtemp(prefix="forge_media_"))

import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine
from sqlalchemy.pool import StaticPool

from app.db import Base, get_session
from app.main import app

_engine = create_async_engine(
    "sqlite+aiosqlite://",
    connect_args={"check_same_thread": False},
    poolclass=StaticPool,
)
_Session = async_sessionmaker(_engine, expire_on_commit=False)


async def _override_get_session():
    async with _Session() as session:
        yield session


app.dependency_overrides[get_session] = _override_get_session


@pytest_asyncio.fixture
async def client():
    async with _engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as c:
        yield c
    async with _engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
