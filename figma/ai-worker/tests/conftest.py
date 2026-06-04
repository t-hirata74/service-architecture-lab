import os

os.environ.setdefault("INTERNAL_TOKEN", "test-internal-token")

import pytest
from fastapi.testclient import TestClient

from main import app

TOKEN = os.environ["INTERNAL_TOKEN"]


@pytest.fixture
def client():
    return TestClient(app)


@pytest.fixture
def auth():
    return {"X-Internal-Token": TOKEN}
