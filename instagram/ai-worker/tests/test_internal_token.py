"""ai-worker への直接アクセスは X-Internal-Token を要求する (defense in depth)。
/health は疎通確認のため open。
"""


def test_recommend_without_token_is_401(raw_client):
    res = raw_client.post("/recommend", json={"user_id": 1, "top_k": 5})
    assert res.status_code == 401


def test_recommend_with_correct_token_passes(raw_client):
    res = raw_client.post(
        "/recommend",
        json={"user_id": 1, "top_k": 5},
        headers={"X-Internal-Token": "dev-internal-token"},
    )
    assert res.status_code == 200


def test_tags_without_token_is_401(raw_client):
    res = raw_client.post("/tags", json={"image_url": "https://x.test/p.jpg"})
    assert res.status_code == 401


def test_health_is_open(raw_client):
    res = raw_client.get("/health")
    assert res.status_code == 200
