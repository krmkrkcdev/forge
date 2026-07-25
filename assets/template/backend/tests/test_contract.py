"""Sözleşme testi — sunucunun çekirdek davranışını docker olmadan doğrular.

Ortak `client` fixture'ı ve test veritabanı kurulumu conftest.py'dedir.

Çalıştırmak için:
    cd backend
    pip install -r requirements-dev.txt
    pytest
"""

from datetime import datetime, timezone


async def test_health(client):
    res = await client.get("/health")
    assert res.status_code == 200
    assert res.json()["status"] == "ok"


async def test_push_then_pull(client):
    now = datetime.now(timezone.utc).isoformat()
    item = {"id": "abc", "title": "Merhaba", "body": "gövde", "updated_at": now}

    res = await client.post("/sync/push", json=[item])
    assert res.status_code == 200
    assert res.json()["accepted"] == 1

    res = await client.get("/sync/pull")
    assert res.status_code == 200
    data = res.json()
    assert len(data) == 1
    assert data[0]["id"] == "abc"
    assert data[0]["title"] == "Merhaba"


async def test_last_write_wins(client):
    old = "2020-01-01T00:00:00+00:00"
    new = "2030-01-01T00:00:00+00:00"
    await client.post(
        "/sync/push",
        json=[{"id": "x", "title": "eski", "body": "", "updated_at": new}],
    )
    # Daha eski updated_at ile gelen güncelleme yok sayılmalı.
    await client.post(
        "/sync/push",
        json=[{"id": "x", "title": "gecikmiş", "body": "", "updated_at": old}],
    )
    data = (await client.get("/sync/pull")).json()
    assert data[0]["title"] == "eski"
