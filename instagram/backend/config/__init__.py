import pymysql

# Django の MySQL ドライバとして PyMySQL を使う (mysqlclient の C ビルドを避けるため)。
# ADR 0003 / architecture.md で MySQL only を方針にしているが、ドライバ選定は ADR 不要の局所判断。
pymysql.install_as_MySQLdb()

from .celery import app as celery_app  # noqa: E402

__all__ = ("celery_app",)
