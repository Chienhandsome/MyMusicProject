"""Admin bearer key or Firebase App Check; no unauthenticated fallback."""
import asyncio
import hashlib
import hmac
import os
from pathlib import Path

from fastapi import HTTPException
import jwt
from jwt import PyJWKClient
from jwt.exceptions import InvalidTokenError, PyJWKClientConnectionError, PyJWKClientError


class DownloadAuth:
    def __init__(self, admin_key="", project_number="", app_ids=frozenset()):
        if admin_key and len(admin_key.encode("utf-8")) < 32:
            raise ValueError("ADMIN_API_KEY must contain at least 32 bytes")
        if bool(project_number) != bool(app_ids):
            raise ValueError("Set both FIREBASE_PROJECT_NUMBER and FIREBASE_APP_IDS")
        if project_number and (not project_number.isascii() or not project_number.isdigit()):
            raise ValueError("FIREBASE_PROJECT_NUMBER must be the numeric project number")
        if any(not app_id.startswith(f"1:{project_number}:") for app_id in app_ids):
            raise ValueError("FIREBASE_APP_IDS must belong to FIREBASE_PROJECT_NUMBER")
        if not admin_key and not project_number:
            raise ValueError("Configure an admin key or Firebase App Check before starting")
        self.admin_digest = hashlib.sha256(admin_key.encode("utf-8")).digest() if admin_key else None
        self.project_number = project_number
        self.app_ids = frozenset(app_ids)
        self.verification_slots = asyncio.Semaphore(2)
        # Public Google keys only: no service-account private key is needed.
        self.jwks = PyJWKClient(
            "https://firebaseappcheck.googleapis.com/v1/jwks",
            cache_jwk_set=True, lifespan=6 * 60 * 60, timeout=5,
        ) if project_number else None

    @classmethod
    def from_environment(cls):
        key = os.getenv("ADMIN_API_KEY", "").strip()
        key_file = os.getenv("ADMIN_API_KEY_FILE", "").strip()
        if key and key_file:
            raise ValueError("Use ADMIN_API_KEY or ADMIN_API_KEY_FILE, not both")
        if key_file:
            key = Path(key_file).read_text(encoding="utf-8").strip()
            if not key:
                raise ValueError("ADMIN_API_KEY_FILE is empty")
        return cls(
            admin_key=key,
            project_number=os.getenv("FIREBASE_PROJECT_NUMBER", "").strip(),
            app_ids=frozenset(item.strip() for item in os.getenv("FIREBASE_APP_IDS", "").split(",") if item.strip()),
        )

    def verify_app_check(self, token):
        headers = jwt.get_unverified_header(token)
        kid = headers.get("kid")
        if (headers.get("alg") != "RS256" or headers.get("typ") != "JWT"
                or not isinstance(kid, str) or not 1 <= len(kid) <= 128):
            raise InvalidTokenError("Invalid App Check JWT header")
        signing_key = self.jwks.get_signing_key_from_jwt(token)
        claims = jwt.decode(
            token, signing_key.key, algorithms=["RS256"],
            audience=f"projects/{self.project_number}",
            issuer=f"https://firebaseappcheck.googleapis.com/{self.project_number}",
            options={"require": ["exp", "iat", "iss", "aud", "sub"]},
        )
        if claims["sub"] not in self.app_ids:
            raise HTTPException(403, "This app is not allowed to download")
        return claims["sub"]

    async def authorize(self, authorization, app_check_token):
        if authorization is not None:
            parts = authorization.split()
            if len(parts) == 2 and parts[0].lower() == "bearer" and self.admin_digest:
                digest = hashlib.sha256(parts[1].encode("utf-8")).digest()
                if hmac.compare_digest(digest, self.admin_digest):
                    return "admin"
            raise HTTPException(401, "Invalid admin credential", headers={"WWW-Authenticate": "Bearer"})
        if not app_check_token:
            raise HTTPException(401, "An admin key or App Check token is required")
        if len(app_check_token) > 8192:
            raise HTTPException(401, "Invalid App Check token")
        if self.jwks is None:
            raise HTTPException(403, "App Check access is not configured")
        # Bound work before the download queue; verification performs blocking key fetches.
        if self.verification_slots.locked():
            raise HTTPException(429, "Authentication is busy", headers={"Retry-After": "5"})
        async with self.verification_slots:
            # Shield the thread so cancelling a request cannot release its slot early.
            task = asyncio.create_task(asyncio.to_thread(self.verify_app_check, app_check_token))
            try:
                return await asyncio.shield(task)
            except asyncio.CancelledError:
                try:
                    await task
                except Exception:
                    pass
                raise
            except PyJWKClientConnectionError as exc:
                raise HTTPException(503, "App verification is temporarily unavailable") from exc
            except (InvalidTokenError, PyJWKClientError, ValueError) as exc:
                raise HTTPException(401, "Invalid or expired App Check token") from exc
