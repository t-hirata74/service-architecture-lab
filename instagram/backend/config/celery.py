"""Celery アプリ。Phase 3 で fan-out task を実装する際に拾う。"""
import os

from celery import Celery

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings")

app = Celery("instagram")
app.config_from_object("django.conf:settings", namespace="CELERY")
app.autodiscover_tasks()
