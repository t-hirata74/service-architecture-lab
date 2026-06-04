def _objs():
    return [
        {"id": "a", "x": 10, "y": 0, "w": 20, "h": 20},
        {"id": "b", "x": 50, "y": 100, "w": 40, "h": 10},
        {"id": "c", "x": 200, "y": 50, "w": 20, "h": 20},
    ]


def test_align_left(client, auth):
    res = client.post("/auto-layout", json={"objects": _objs(), "mode": "align-left"}, headers=auth)
    assert res.status_code == 200
    xs = {u["id"]: u["x"] for u in res.json()["updates"]}
    assert xs == {"a": 10, "b": 10, "c": 10}  # 全 x = min(x)=10


def test_align_right(client, auth):
    res = client.post("/auto-layout", json={"objects": _objs(), "mode": "align-right"}, headers=auth)
    ups = {u["id"]: u["x"] for u in res.json()["updates"]}
    # 右端 = max(x+w) = 220。各 x = 220 - w。
    assert ups == {"a": 200, "b": 180, "c": 200}


def test_align_top(client, auth):
    res = client.post("/auto-layout", json={"objects": _objs(), "mode": "align-top"}, headers=auth)
    ys = {u["id"]: u["y"] for u in res.json()["updates"]}
    assert ys == {"a": 0, "b": 0, "c": 0}


def test_distribute_h_keeps_ends_and_equalizes_gaps(client, auth):
    res = client.post("/auto-layout", json={"objects": _objs(), "mode": "distribute-h"}, headers=auth)
    ups = {u["id"]: u["x"] for u in res.json()["updates"]}
    # 端 (a=10, c=200..220) は固定。間の余白を均等割り。
    assert ups["a"] == 10
    assert ups["c"] == 200
    # span=210, 合計幅=80 → gap=(210-80)/2=65。b は a の右端(30)+gap(65)=95。
    assert ups["b"] == 95


def test_under_two_objects_is_noop(client, auth):
    res = client.post("/auto-layout", json={"objects": [{"id": "a", "x": 5, "y": 5}], "mode": "align-left"}, headers=auth)
    assert res.json()["updates"] == []


def test_unknown_mode_422(client, auth):
    res = client.post("/auto-layout", json={"objects": _objs(), "mode": "spiral"}, headers=auth)
    assert res.status_code == 422
