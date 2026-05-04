from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, String, Text, UniqueConstraint, func
from sqlalchemy.orm import Mapped, mapped_column

from app.db import Base


class Subreddit(Base):
    __tablename__ = "subreddits"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(String(64), unique=True, nullable=False)
    description: Mapped[str] = mapped_column(Text, nullable=False, default="")
    created_by: Mapped[int] = mapped_column(ForeignKey("users.id"), nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=False), server_default=func.now(), nullable=False
    )


class SubredditMembership(Base):
    __tablename__ = "subreddit_memberships"
    __table_args__ = (
        UniqueConstraint("subreddit_id", "user_id", name="uq_subreddit_memberships"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    subreddit_id: Mapped[int] = mapped_column(ForeignKey("subreddits.id"), nullable=False)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=False), server_default=func.now(), nullable=False
    )
