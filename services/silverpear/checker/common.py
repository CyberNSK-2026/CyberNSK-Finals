from __future__ import annotations

import datetime as dt
import hashlib
import http.cookiejar
import json
import pathlib
import random
import re
import urllib.error
import urllib.parse
import urllib.request
import uuid
from dataclasses import dataclass
from typing import Any, Iterable

DEFAULT_PORT = 7777
DEFAULT_TIMEOUT = 10
NOTE_SLOTS = ("top", "middle", "base")
GO_RNG_LEN = 607
GO_RNG_TAP = 273
INT32_MAX = (1 << 31) - 1
INT64_MASK = (1 << 64) - 1
INT63_MASK = (1 << 63) - 1


class SilverPearError(RuntimeError):
    pass


class HttpError(SilverPearError):
    def __init__(self, method: str, path: str, status: int, payload: Any):
        self.method = method
        self.path = path
        self.status = status
        self.payload = payload
        super().__init__(f"{method} {path} failed with HTTP {status}: {payload}")


def normalize_base_url(target: str) -> str:
    value = target.strip()
    if not value:
        raise ValueError("target is required")
    if "://" not in value:
        value = f"http://{value}"

    parsed = urllib.parse.urlparse(value)
    if not parsed.netloc:
        raise ValueError(f"invalid target: {target}")

    netloc = parsed.netloc
    if ":" not in netloc:
        netloc = f"{netloc}:{DEFAULT_PORT}"

    normalized = parsed._replace(netloc=netloc, path="", params="", query="", fragment="")
    return normalized.geturl().rstrip("/")


def parse_rfc3339(value: str) -> dt.datetime:
    return dt.datetime.fromisoformat(value.replace("Z", "+00:00"))


def random_suffix(length: int = 8) -> str:
    return uuid.uuid4().hex[:length]


def random_name(prefix: str) -> str:
    return f"{prefix}_{random_suffix()}"


def username_hash(value: str) -> str:
    return hashlib.sha1(value.lower().encode()).hexdigest()[:8]


def choose_note_slot() -> str:
    return random.choice(NOTE_SLOTS)


def make_flag_description(flag: str, note_slot: str) -> dict[str, str]:
    if note_slot not in NOTE_SLOTS:
        raise ValueError(f"invalid note slot: {note_slot}")

    payload = {
        "description": "A layered perfume that starts bright and settles into a dense evening accord.",
        "top": "sparkling pear, bergamot, cold aldehydes",
        "middle": "iris butter, violet leaf, silver tea",
        "base": "musk veil, pale cedar, mineral amber",
    }
    payload[note_slot] = flag
    return payload


@dataclass(frozen=True)
class FlagState:
    product_id: int
    note_slot: str
    buyer_name: str
    buyer_password: str

    def dumps(self) -> str:
        return json.dumps(
            {
                "product_id": self.product_id,
                "note_slot": self.note_slot,
                "buyer_name": self.buyer_name,
                "buyer_password": self.buyer_password,
            },
            separators=(",", ":"),
            sort_keys=True,
        )

    @classmethod
    def loads(cls, raw: str) -> "FlagState":
        value = raw.strip()
        if value.startswith("{"):
            payload = json.loads(value)
            return cls(
                int(payload["product_id"]),
                str(payload["note_slot"]),
                str(payload["buyer_name"]),
                str(payload["buyer_password"]),
            )
        product_id, note_slot, buyer_name, buyer_password = value.split(":", 3)
        return cls(int(product_id), note_slot, buyer_name, buyer_password)


class SilverPearClient:
    def __init__(self, base_url: str, timeout: int = DEFAULT_TIMEOUT):
        self.base_url = normalize_base_url(base_url)
        self.timeout = timeout
        self.cookies = http.cookiejar.CookieJar()
        self.opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(self.cookies))

    def request(
        self,
        method: str,
        path: str,
        payload: Any | None = None,
        expected: Iterable[int] = (200, 201),
    ) -> tuple[int, Any]:
        data = None
        headers: dict[str, str] = {}
        if payload is not None:
            data = json.dumps(payload).encode()
            headers["Content-Type"] = "application/json"

        request = urllib.request.Request(self.base_url + path, data=data, method=method, headers=headers)
        try:
            with self.opener.open(request, timeout=self.timeout) as response:
                body = response.read().decode()
                parsed = json.loads(body) if body else None
                if response.status not in set(expected):
                    raise HttpError(method, path, response.status, parsed)
                return response.status, parsed
        except urllib.error.HTTPError as exc:
            body = exc.read().decode()
            parsed = json.loads(body) if body else None
            if exc.code not in set(expected):
                raise HttpError(method, path, exc.code, parsed) from exc
            return exc.code, parsed

    def health(self) -> dict[str, Any]:
        return self.request("GET", "/api/health", (None), (200,))[1]

    def storefront(self) -> dict[str, Any]:
        return self.request("GET", "/api/storefront", expected=(200,))[1]

    def get_product(self, product_id: int) -> dict[str, Any]:
        return self.request("GET", f"/api/products/{product_id}", expected=(200,))[1]

    def list_brands(self) -> dict[str, Any]:
        return self.request("GET", "/api/brands", expected=(200,))[1]

    def register(self, name: str, password: str, role: str, status: str | None = None) -> dict[str, Any]:
        payload: dict[str, Any] = {"name": name, "password": password, "role": role}
        if status is not None:
            payload["status"] = status
        return self.request("POST", "/api/register", payload, expected=(201,))[1]

    def login(self, name: str, password: str) -> dict[str, Any]:
        return self.request("POST", "/api/login", {"name": name, "password": password}, expected=(200,))[1]

    def logout(self) -> dict[str, Any]:
        return self.request("POST", "/api/logout", payload={}, expected=(200,))[1]

    def me(self) -> dict[str, Any]:
        return self.request("GET", "/api/me", expected=(200,))[1]

    def create_product(self, brand_id: int, title: str, short_description: str, price: int) -> dict[str, Any]:
        payload = {
            "brand_id": brand_id,
            "title": title,
            "short_description": short_description,
            "price": price,
        }
        return self.request("POST", "/api/products", payload, expected=(201,))[1]

    def create_description(self, product_id: int, description: dict[str, str]) -> dict[str, Any]:
        return self.request(
            "POST",
            f"/api/products/{product_id}/description",
            description,
            expected=(201,),
        )[1]

    def spin_wheel(self) -> dict[str, Any]:
        return self.request("POST", "/api/wheel/spin", payload={}, expected=(200,))[1]

    def create_order(self) -> dict[str, Any]:
        return self.request("POST", "/api/orders", payload={}, expected=(201,))[1]

    def add_order_item(self, public_id: str, product_id: int, quantity: int = 1) -> dict[str, Any]:
        payload = {"product_id": product_id, "quantity": quantity}
        return self.request("POST", f"/api/orders/{public_id}/items", payload, expected=(200,))[1]

    def list_orders(self) -> dict[str, Any]:
        return self.request("GET", "/api/orders", expected=(200,))[1]

    def get_order(self, public_id: str) -> dict[str, Any]:
        return self.request("GET", f"/api/orders/{public_id}", expected=(200,))[1]

    def checkout_order(self, public_id: str) -> dict[str, Any]:
        return self.request("POST", f"/api/orders/{public_id}/checkout", payload={}, expected=(200,))[1]

    def apply_promocode(self, public_id: str, code: str) -> dict[str, Any]:
        return self.request(
            "POST",
            f"/api/orders/{public_id}/apply-promocode",
            {"code": code},
            expected=(200,),
        )[1]

    def get_notes(self, product_id: int, expected: Iterable[int] = (200,)) -> tuple[int, Any]:
        return self.request("GET", f"/api/products/{product_id}/notes", expected=expected)

    def get_list_transaction(self, list_id: int, expected: Iterable[int] = (200,)) -> tuple[int, Any]:
        return self.request("GET", f"/api/list_transaction/{list_id}", expected=expected)

    def get_transaction(self, public_id: str, expected: Iterable[int] = (200,)) -> tuple[int, Any]:
        return self.request("GET", f"/api/transactions/{public_id}", expected=expected)


def register_and_login(
    base_url: str,
    prefix: str = "user",
    role: str = "buyer",
    status: str | None = None,
) -> tuple[SilverPearClient, str, str]:
    name = random_name(prefix)
    password = f"pw_{random_suffix(10)}"
    client = SilverPearClient(base_url)
    client.register(name, password, role=role, status=status)
    client.login(name, password)
    return client, name, password


def pick_brand_id(client: SilverPearClient) -> int:
    brands = client.list_brands()["brands"]
    if not brands:
        raise SilverPearError("brand seed is missing")
    return int(brands[0]["id"])


def create_product_with_flag(
    seller: SilverPearClient,
    flag: str,
    price: int,
    note_slot: str | None = None,
    title_prefix: str = "SilverPear",
) -> dict[str, Any]:
    slot = note_slot or choose_note_slot()
    brand_id = pick_brand_id(seller)
    title = f"{title_prefix} {random_suffix(6)}"
    short_description = "A cold metallic perfume with a bright pear opening and a dark resin finish."
    product = seller.create_product(brand_id, title, short_description, price)["product"]
    description = make_flag_description(flag, slot)
    seller.create_description(int(product["id"]), description)
    return {"product": product, "note_slot": slot, "description": description}


def create_and_purchase_flag_product(
    seller: SilverPearClient,
    buyer: SilverPearClient,
    flag: str,
    price: int = 3500,
    note_slot: str | None = None,
    title_prefix: str = "Flag Scent",
) -> dict[str, Any]:
    created = create_product_with_flag(seller, flag, price=price, note_slot=note_slot, title_prefix=title_prefix)
    product = created["product"]
    order = buyer.create_order()["order"]
    order = buyer.add_order_item(order["public_id"], int(product["id"]), quantity=1)["order"]
    list_id = int(order["items"][0]["id"])
    order = buyer.checkout_order(order["public_id"])["order"]

    return {
        "product_id": int(product["id"]),
        "note_slot": created["note_slot"],
        "list_id": list_id,
        "order_public_id": order["public_id"],
        "price": int(product["price"]),
    }


def recover_service_start_unix(base_url: str) -> int:
    sale_ends_at = SilverPearClient(base_url).storefront()["sale_ends_at"]
    sale_end = parse_rfc3339(sale_ends_at)
    start = sale_end - dt.timedelta(hours=72)
    return int(start.timestamp())


def predict_jackpot_code(service_start_unix: int, username: str) -> str:
    alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    rng = GoMathRand(service_start_unix)
    token = "".join(alphabet[rng.intn(len(alphabet))] for _ in range(10))
    return f"{token}-{username_hash(username)}"


def to_int64(value: int) -> int:
    value &= INT64_MASK
    if value >= 1 << 63:
        value -= 1 << 64
    return value


def _load_rng_cooked() -> list[int]:
    source_path = pathlib.Path(__file__).resolve().parent / "rng_go_source.txt"
    text = source_path.read_text(encoding="utf-8")
    match = re.search(r"rngCooked\s+\[rngLen\]int64\s*=\s*\[\.\.\.\]int64\{(.*?)\n\t\}", text, re.S)
    if not match:
        raise SilverPearError(f"failed to parse rngCooked from {source_path}")
    numbers = [int(item.strip()) for item in match.group(1).replace("\n", " ").split(",") if item.strip()]
    if len(numbers) != GO_RNG_LEN:
        raise SilverPearError(f"unexpected rngCooked length: {len(numbers)}")
    return numbers


_RNG_COOKED = _load_rng_cooked()


class GoMathRand:
    def __init__(self, seed: int):
        self.tap = 0
        self.feed = 0
        self.vec = [0] * GO_RNG_LEN
        self.seed(seed)

    @staticmethod
    def seedrand(value: int) -> int:
        a = 48271
        q = 44488
        r = 3399
        hi = value // q
        lo = value % q
        value = a * lo - r * hi
        if value < 0:
            value += INT32_MAX
        return value

    def seed(self, seed: int) -> None:
        self.tap = 0
        self.feed = GO_RNG_LEN - GO_RNG_TAP
        seed %= INT32_MAX
        if seed < 0:
            seed += INT32_MAX
        if seed == 0:
            seed = 89482311

        x = seed
        for i in range(-20, GO_RNG_LEN):
            x = self.seedrand(x)
            if i >= 0:
                value = to_int64(x << 40)
                x = self.seedrand(x)
                value = to_int64(value ^ (x << 20))
                x = self.seedrand(x)
                value = to_int64(value ^ x)
                value = to_int64(value ^ _RNG_COOKED[i])
                self.vec[i] = value

    def uint64(self) -> int:
        self.tap -= 1
        if self.tap < 0:
            self.tap += GO_RNG_LEN

        self.feed -= 1
        if self.feed < 0:
            self.feed += GO_RNG_LEN

        value = to_int64(self.vec[self.feed] + self.vec[self.tap])
        self.vec[self.feed] = value
        return value & INT64_MASK

    def int63(self) -> int:
        return self.uint64() & INT63_MASK

    def int31(self) -> int:
        return int(self.int63() >> 32)

    def int31n(self, bound: int) -> int:
        if bound <= 0:
            raise ValueError("bound must be positive")
        if bound & (bound - 1) == 0:
            return self.int31() & (bound - 1)
        limit = (1 << 31) - 1 - ((1 << 31) % bound)
        value = self.int31()
        while value > limit:
            value = self.int31()
        return value % bound

    def intn(self, bound: int) -> int:
        if bound <= 0:
            raise ValueError("bound must be positive")
        if bound <= (1 << 31) - 1:
            return self.int31n(bound)
        limit = (1 << 63) - 1 - ((1 << 63) % bound)
        value = self.int63()
        while value > limit:
            value = self.int63()
        return value % bound
