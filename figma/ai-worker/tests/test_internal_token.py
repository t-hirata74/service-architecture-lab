def test_auto_layout_requires_token(client):
    res = client.post("/auto-layout", json={"objects": [], "mode": "align-left"})
    assert res.status_code == 401


def test_lint_requires_token(client):
    res = client.post("/lint", json={"objects": []})
    assert res.status_code == 401


def test_wrong_token_rejected(client):
    res = client.post("/lint", json={"objects": []}, headers={"X-Internal-Token": "nope"})
    assert res.status_code == 401
