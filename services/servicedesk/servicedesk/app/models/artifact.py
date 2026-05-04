import uuid
from sqlalchemy import String, Text, ForeignKey, DateTime, func, BigInteger
from sqlalchemy.orm import Mapped, mapped_column, relationship
from database import Base


class Artifact(Base):
    __tablename__ = "artifacts"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    public_ref: Mapped[int] = mapped_column(BigInteger, unique=True, nullable=True)
    ticket_id: Mapped[str] = mapped_column(ForeignKey("tickets.id"), nullable=False)
    filename: Mapped[str] = mapped_column(String(256), nullable=False)
    description: Mapped[str] = mapped_column(Text, nullable=True)
    content_type: Mapped[str] = mapped_column(String(64), nullable=True)
    file_size: Mapped[int] = mapped_column(BigInteger, default=0)
    storage_path: Mapped[str] = mapped_column(String(512), nullable=False)

    uploaded_at: Mapped[str] = mapped_column(DateTime(timezone=True), server_default=func.now())

    ticket: Mapped["Ticket"] = relationship("Ticket", back_populates="artifacts")
