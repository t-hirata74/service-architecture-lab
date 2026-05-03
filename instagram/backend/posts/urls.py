from django.urls import path

from . import views

urlpatterns = [
    path("posts", views.post_list_create, name="post-list-create"),
    path("posts/<int:pk>", views.post_detail, name="post-detail"),
    path("posts/<int:pk>/like", views.like, name="post-like"),
    path("posts/<int:pk>/comments", views.comment_list_create, name="post-comments"),
    path("users/<str:username>/posts", views.user_posts, name="user-posts"),
]
