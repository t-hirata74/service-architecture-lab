def test_detects_overlap(client, auth):
    objs = [
        {"id": "a", "x": 0, "y": 0, "w": 40, "h": 40},
        {"id": "b", "x": 20, "y": 20, "w": 40, "h": 40},  # a と重なる
        {"id": "c", "x": 200, "y": 200, "w": 8, "h": 8},   # 重ならない
    ]
    res = client.post("/lint", json={"objects": objs, "grid": 8}, headers=auth)
    assert res.status_code == 200
    overlaps = [i for i in res.json()["issues"] if i["kind"] == "overlap"]
    assert {"object_id": "a", "kind": "overlap", "other_id": "b"} in overlaps


def test_detects_off_grid_with_suggestion(client, auth):
    objs = [{"id": "a", "x": 13, "y": 21, "w": 8, "h": 8}]  # grid 8 に乗っていない
    res = client.post("/lint", json={"objects": objs, "grid": 8}, headers=auth)
    issues = res.json()["issues"]
    off = next(i for i in issues if i["kind"] == "off_grid")
    assert off["object_id"] == "a"
    assert off["suggestion"] == {"x": 16, "y": 24}  # 最近接グリッド


def test_on_grid_no_off_grid_issue(client, auth):
    objs = [{"id": "a", "x": 16, "y": 24, "w": 8, "h": 8}]
    res = client.post("/lint", json={"objects": objs, "grid": 8}, headers=auth)
    assert all(i["kind"] != "off_grid" for i in res.json()["issues"])
