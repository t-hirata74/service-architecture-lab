from django.urls import path

from . import views

urlpatterns = [
    path("users/<str:username>", views.user_detail, name="user-detail"),
]
