"""タグ抽出 mock の検証。deterministic なので同じ URL に対して常に同じ結果。"""


def test_tags_deterministic(client):
    res1 = client.post("/tags", json={"image_url": "https://example.test/cat.jpg"})
    res2 = client.post("/tags", json={"image_url": "https://example.test/cat.jpg"})
    assert res1.status_code == 200
    assert res1.json() == res2.json()


def test_tags_returns_3_to_5_tags(client):
    res = client.post("/tags", json={"image_url": "https://example.test/x.jpg"})
    tags = res.json()["tags"]
    assert 3 <= len(tags) <= 5


def test_tags_unique(client):
    res = client.post("/tags", json={"image_url": "https://example.test/y.jpg"})
    tags = res.json()["tags"]
    assert len(tags) == len(set(tags))


def test_tags_different_urls_different_tags(client):
    res_a = client.post("/tags", json={"image_url": "url-a"})
    res_b = client.post("/tags", json={"image_url": "url-b"})
    # SHA-256 の collision でない限り違う tag set になる
    assert res_a.json() != res_b.json()
