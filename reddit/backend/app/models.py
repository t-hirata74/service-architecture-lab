"""Aggregate model imports.

Importing this module ensures every mapped class is registered on
``Base.metadata`` before ``create_all`` / migrations run.
"""

from app.domain.accounts.models import User  # noqa: F401
from app.domain.subreddits.models import Subreddit, SubredditMembership  # noqa: F401
from app.domain.posts.models import Post  # noqa: F401
from app.domain.comments.models import Comment  # noqa: F401
from app.domain.votes.models import Vote, VoteTargetType  # noqa: F401
