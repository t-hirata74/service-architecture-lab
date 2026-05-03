from django.contrib import admin
from django.http import JsonResponse
from django.urls import include, path


def health(_request):
    return JsonResponse({"ok": True})


urlpatterns = [
    path("admin/", admin.site.urls),
    path("health", health),
    path("auth/", include("accounts.urls")),
    path("", include("accounts.urls_users")),
    path("", include("posts.urls")),
    path("", include("follows.urls")),
    path("", include("timeline.urls")),
]
