"""Discovery feed の mock 動作検証。

- 自分の post は除外
- フォロー中ユーザの post は除外
- soft-deleted post は除外
- created_at desc で並ぶ
- top_k で件数を絞る
"""
def test_recommend_excludes_self_and_followed(client):
    res = client.post("/recommend", json={"user_id": 1, "top_k": 10})
    assert res.status_code == 200
    ids = res.json()["post_ids"]
    assert 14 not in ids, "self post"
    assert 10 not in ids, "followed user's post"
    assert 13 not in ids, "soft-deleted post"
    assert ids == [12, 11], "remaining posts in created_at desc"


def test_recommend_respects_top_k(client):
    res = client.post("/recommend", json={"user_id": 1, "top_k": 1})
    assert res.status_code == 200
    assert res.json()["post_ids"] == [12]  # 最新 1 件のみ


def test_recommend_validates_top_k_range(client):
    res = client.post("/recommend", json={"user_id": 1, "top_k": 0})
    assert res.status_code == 422
    res = client.post("/recommend", json={"user_id": 1, "top_k": 999})
    assert res.status_code == 422
