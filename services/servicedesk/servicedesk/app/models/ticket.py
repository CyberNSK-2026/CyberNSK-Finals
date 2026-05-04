import uuid
import enum
from sqlalchemy import String, Text, Enum as SAEnum, ForeignKey, DateTime, func
from sqlalchemy.orm import Mapped, mapped_column, relationship
from database import Base


class TicketStatus(str, enum.Enum):
    backlog = "backlog"
    open = "open"
    closed = "closed"


class TicketPriority(str, enum.Enum):
    low = "low"
    medium = "medium"
    high = "high"


class Ticket(Base):
    __tablename__ = "tickets"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    case_number: Mapped[str] = mapped_column(String(32), unique=True, nullable=True)
    title: Mapped[str] = mapped_column(String(256), nullable=False)
    description: Mapped[str] = mapped_column(Text, nullable=True)
    vendor_case_id: Mapped[str] = mapped_column(String(128), nullable=True)
    device_serial: Mapped[str] = mapped_column(String(128), nullable=True)
    automation_secret: Mapped[str] = mapped_column(String(256), nullable=True)
    status: Mapped[TicketStatus] = mapped_column(SAEnum(TicketStatus, native_enum=False), default=TicketStatus.backlog)
    priority: Mapped[TicketPriority] = mapped_column(SAEnum(TicketPriority, native_enum=False), default=TicketPriority.medium)

    customer_id: Mapped[str] = mapped_column(ForeignKey("users.id"), nullable=False)
    agent_id: Mapped[str] = mapped_column(ForeignKey("users.id"), nullable=True)

    report_template: Mapped[str] = mapped_column(
        Text,
        nullable=True,
        default="Ticket {{ ticket.title }} — Status: {{ ticket.status }}"
    )
    resolution: Mapped[str] = mapped_column(Text, nullable=True)

    created_at: Mapped[str] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[str] = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

    customer: Mapped["User"] = relationship("User", back_populates="tickets", foreign_keys=[customer_id])
    agent: Mapped["User"] = relationship("User", back_populates="assigned_tickets", foreign_keys=[agent_id])
    artifacts: Mapped[list] = relationship("Artifact", back_populates="ticket", cascade="all, delete-orphan")
    share_tokens: Mapped[list] = relationship("ShareToken", back_populates="ticket", cascade="all, delete-orphan")
    messages: Mapped[list] = relationship("TicketMessage", back_populates="ticket", cascade="all, delete-orphan")
