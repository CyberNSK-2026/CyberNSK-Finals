import uuid
from sqlalchemy import String, Boolean, Integer, Enum as SAEnum
from sqlalchemy.orm import Mapped, mapped_column, relationship
from database import Base
import enum


class UserRole(str, enum.Enum):
    customer = "customer"
    agent = "agent"


class User(Base):
    __tablename__ = "users"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    username: Mapped[str] = mapped_column(String(64), unique=True, nullable=False)
    email: Mapped[str] = mapped_column(String(128), unique=True, nullable=False)
    hashed_password: Mapped[str] = mapped_column(String(256), nullable=False)
    role: Mapped[UserRole] = mapped_column(SAEnum(UserRole, native_enum=False), default=UserRole.customer)
    vip_status: Mapped[bool] = mapped_column(Boolean, default=False)
    access_level: Mapped[int] = mapped_column(Integer, default=1)  # 1-5
    workspace: Mapped[str] = mapped_column(String(32), default="portal")
    queue_scope: Mapped[str] = mapped_column(String(32), default="personal")
    contact_phone: Mapped[str] = mapped_column(String(128), default="")

    tickets: Mapped[list] = relationship("Ticket", back_populates="customer", foreign_keys="Ticket.customer_id")
    assigned_tickets: Mapped[list] = relationship("Ticket", back_populates="agent", foreign_keys="Ticket.agent_id")
    integrations: Mapped[list] = relationship("Integration", back_populates="owner")
    ticket_messages: Mapped[list] = relationship("TicketMessage", back_populates="author")
