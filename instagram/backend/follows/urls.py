from django.urls import path

from . import views

urlpatterns = [
    path("users/<str:username>/follow", views.follow, name="follow"),
    path("users/<str:username>/followers", views.followers, name="followers"),
    path("users/<str:username>/following", views.following, name="following"),
]
