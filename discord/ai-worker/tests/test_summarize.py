def test_summarize_empty(client, auth_headers) -> None:
    r = client.post("/summarize", headers=auth_headers, json={"messages": []})
    assert r.status_code == 200
    body = r.json()
    assert body["message_count"] == 0
    assert body["top_speakers"] == []
    assert "no messages" in body["summary"]


def test_summarize_top_speakers(client, auth_headers) -> None:
    msgs = (
        [{"username": "alice", "body": "hello world"}] * 3
        + [{"username": "bob", "body": "deploy pipeline failing"}] * 2
        + [{"username": "carol", "body": "lunch"}]
    )
    r = client.post("/summarize", headers=auth_headers, json={"messages": msgs})
    assert r.status_code == 200
    body = r.json()
    assert body["message_count"] == 6
    assert body["top_speakers"][0] == "alice"
    assert "alice" in body["summary"]


def test_summarize_filters_stopwords(client, auth_headers) -> None:
    msgs = [
        {"username": "u", "body": "the quick brown fox jumps over the lazy dog"},
        {"username": "u", "body": "the brown dog is the brown dog"},
    ]
    r = client.post("/summarize", headers=auth_headers, json={"messages": msgs})
    assert r.status_code == 200
    summary = r.json()["summary"].lower()
    # stopwords like "the" / "is" must not appear in topics list
    topics = summary.split("topics:")[1]
    assert " the " not in f" {topics} "


def test_summarize_deterministic(client, auth_headers) -> None:
    msgs = [{"username": "alice", "body": "ship it"}, {"username": "bob", "body": "lgtm"}]
    a = client.post("/summarize", headers=auth_headers, json={"messages": msgs}).json()
    b = client.post("/summarize", headers=auth_headers, json={"messages": msgs}).json()
    assert a == b
