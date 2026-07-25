"""Fotoğraf uçlarının testi — yükle, çek, listele, reddet.

İçerik doğrulaması content-type üzerinden yapılır (gerçek PNG çözümlenmez), o
yüzden sahte baytlar yeterli; tur (upload → fetch) baytların korunduğunu sınar.
"""

_PNG = b"\x89PNG\r\n\x1a\n sahte foto verisi"


async def test_upload_fetch_list(client):
    files = {"file": ("foto.png", _PNG, "image/png")}
    res = await client.post("/media", files=files, data={"id": "photo1"})
    assert res.status_code == 200, res.text
    body = res.json()
    assert body["id"] == "photo1"
    assert body["content_type"] == "image/png"
    assert body["size"] == len(_PNG)

    # Statik çekme: aynı baytlar geri gelmeli.
    res = await client.get("/media/photo1")
    assert res.status_code == 200
    assert res.headers["content-type"].startswith("image/png")
    assert res.content == _PNG

    # Listeleme.
    res = await client.get("/media")
    assert "photo1" in [m["id"] for m in res.json()]


async def test_reject_non_image(client):
    files = {"file": ("x.txt", b"merhaba", "text/plain")}
    res = await client.post("/media", files=files)
    assert res.status_code == 415


async def test_delete_tombstones(client):
    files = {"file": ("a.png", _PNG, "image/png")}
    await client.post("/media", files=files, data={"id": "sil"})

    res = await client.delete("/media/sil")
    assert res.status_code == 200
    assert res.json()["deleted"] is True

    # Silinen artık çekilemez ve listede görünmez.
    assert (await client.get("/media/sil")).status_code == 404
    assert "sil" not in [m["id"] for m in (await client.get("/media")).json()]
