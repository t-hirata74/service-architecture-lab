import pytest
from fastapi.testclient import TestClient

from main import INTERNAL_TOKEN, app


@pytest.fixture
def client() -> TestClient:
    return TestClient(app)


@pytest.fixture
def auth_headers() -> dict[str, str]:
    return {"X-Internal-Token": INTERNAL_TOKEN}
