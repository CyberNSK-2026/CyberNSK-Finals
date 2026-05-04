"""
Локальная проверка подписи в том же виде, что token-verfer (Main.java):

- message — UTF-8 строка. Для SSO в CheckD: ``sso-token=<base64>`` (то, что уходит в token-verfer).
- SHA-256(message), блок длины k = ceil(modulus_bits / 8), хэш прижат к **правому** краю, слева нули.
- Подпись: RSA **private** decrypt без паддинга над этим блоком → байты подписи.
- Проверка: RSA **public** encrypt без паддинга над подписью → блок, сравнение с ожидаемым (constant-time).

Алгоритм: RSA/ECB/NoPadding в режиме DECRYPT (подпись) / ENCRYPT (проверка), как в Java.
"""

from __future__ import annotations

import base64
import binascii
import hashlib
import secrets

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.rsa import RSAPublicKey


def load_rsa_public_key(raw: bytes) -> RSAPublicKey:
    """X.509 SubjectPublicKeyInfo (DER), как пишет token-verfer в ``keys/public.key``."""
    try:
        key = serialization.load_der_public_key(raw)
    except ValueError:
        key = serialization.load_pem_public_key(raw)
    if not isinstance(key, RSAPublicKey):
        raise TypeError("expected RSA public key")
    return key


def build_rsa_block_from_message(message: str, pub: RSAPublicKey) -> bytes:
    data = message.encode("utf-8")
    digest = hashlib.sha256(data).digest()
    k = (pub.key_size + 7) // 8
    block = bytearray(k)
    block[k - len(digest) :] = digest
    return bytes(block)


def _constant_time_eq(a: bytes, b: bytes) -> bool:
    if len(a) != len(b):
        return False
    return secrets.compare_digest(a, b)


def verify_token_verfer_style(message: str, signature_b64: str, pub: RSAPublicKey) -> bool:
    """Эквивалент POST /validate на token-verfer (без HTTP)."""
    try:
        # Python < 3.11: standard_b64decode() без аргумента validate
        sig = base64.standard_b64decode(signature_b64)
    except (ValueError, binascii.Error):
        return False

    expected_block = build_rsa_block_from_message(message, pub)
    k = len(expected_block)
    n = pub.public_numbers().n
    e = pub.public_numbers().e
    sig_int = int.from_bytes(sig, "big")
    if sig_int < 0 or sig_int >= n:
        return False
    actual_int = pow(sig_int, e, n)
    actual_block = actual_int.to_bytes(k, "big")
    return _constant_time_eq(expected_block, actual_block)
