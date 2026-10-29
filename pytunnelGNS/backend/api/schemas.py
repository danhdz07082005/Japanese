"""Pydantic schemas for PyTunnel REST API."""
from pydantic import BaseModel


class ParseRequest(BaseModel):
    raw_input: str


class CreateTunnelRequest(BaseModel):
    target_input: str
    is_public: bool = False


class ToggleModeRequest(BaseModel):
    is_public: bool
    keep_sessions: bool = True


class RotateCodeRequest(BaseModel):
    revoke_all: bool = False


class ShortenLinkRequest(BaseModel):
    alias: str = ""

