"""İstemci ile sunucu arasındaki veri sözleşmesi (Pydantic).

Bu şema, app tarafındaki `test/api_contract_test.dart` ile aynı alanları
taşımalı; sözleşme testi ikisinin uyumlu kalmasını güvence altına alır.
"""

from datetime import datetime

from pydantic import BaseModel


class Item(BaseModel):
    id: str
    title: str = ""
    body: str = ""
    updated_at: datetime
    deleted: bool = False

    model_config = {"from_attributes": True}


class PushResult(BaseModel):
    accepted: int
    server_time: datetime


class Media(BaseModel):
    id: str
    filename: str
    content_type: str
    size: int
    created_at: datetime
    deleted: bool = False

    model_config = {"from_attributes": True}
