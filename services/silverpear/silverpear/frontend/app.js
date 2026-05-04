"use strict";

const root = document.getElementById("root");

const state = {
  booting: true,
  health: null,
  storefront: { sale_ends_at: null, brands: [] },
  user: null,
  orders: [],
  selectedOrderId: null,
  selectedOrder: null,
  activeDraftOrderId: null,
  brands: [],
  notes: {},
  wheelResult: null,
  seller: {
    lastCreatedProductId: "",
  },
  ui: {
    pending: 0,
    banner: null,
    productBusy: {},
    loadingOrder: false,
    spinningWheel: false,
  },
  formCache: {},
};

class ApiError extends Error {
  constructor(status, payload, fallbackMessage) {
    const message = payload?.error || fallbackMessage || `HTTP ${status}`;
    super(message);
    this.status = status;
    this.payload = payload;
  }
}

function escapeHtml(value) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

function formatPrice(value) {
  return `${Number(value || 0).toLocaleString("en-US")} silvers`;
}

function formatDate(value) {
  if (!value) {
    return "not set";
  }

  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return value;
  }

  return date.toLocaleString("en-GB", {
    year: "numeric",
    month: "short",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
  });
}

function formatCountdown(target) {
  if (!target) {
    return "72:00:00";
  }

  const diff = new Date(target).getTime() - Date.now();
  if (diff <= 0) {
    return "sale closed";
  }

  const totalSeconds = Math.floor(diff / 1000);
  const days = Math.floor(totalSeconds / 86400);
  const hours = Math.floor((totalSeconds % 86400) / 3600);
  const minutes = Math.floor((totalSeconds % 3600) / 60);
  const seconds = totalSeconds % 60;
  return `${String(days).padStart(2, "0")}:${String(hours).padStart(2, "0")}:${String(minutes).padStart(2, "0")}:${String(seconds).padStart(2, "0")}`;
}

function setBanner(type, text) {
  state.ui.banner = { type, text };
  render();
}

function clearBanner() {
  state.ui.banner = null;
}

function setPending(delta) {
  state.ui.pending = Math.max(0, state.ui.pending + delta);
  render();
}

async function api(path, options = {}) {
  const {
    method = "GET",
    body,
    expected = [200],
    timeout = 12000,
  } = options;

  const controller = new AbortController();
  const timer = window.setTimeout(() => controller.abort(), timeout);
  let response;

  try {
    response = await fetch(path, {
      method,
      credentials: "same-origin",
      headers: body ? { "Content-Type": "application/json" } : {},
      body: body ? JSON.stringify(body) : undefined,
      signal: controller.signal,
    });
  } catch (error) {
    if (error?.name === "AbortError") {
      throw new Error(`Request timeout while loading ${path}`);
    }
    throw error;
  } finally {
    window.clearTimeout(timer);
  }

  let payload = null;
  const raw = await response.text();
  if (raw) {
    try {
      payload = JSON.parse(raw);
    } catch (_error) {
      payload = { raw };
    }
  }

  if (!expected.includes(response.status)) {
    throw new ApiError(response.status, payload, `${method} ${path} failed`);
  }

  return { status: response.status, payload };
}

function getCachedValue(key, fallback = "") {
  return state.formCache[key] ?? fallback;
}

function storeInputValue(element) {
  const key = element.dataset.persist;
  if (!key) {
    return;
  }
  state.formCache[key] = element.value;
}

function clearCachedValues(keys) {
  for (const key of keys) {
    delete state.formCache[key];
  }
}

function delay(ms) {
  return new Promise((resolve) => {
    window.setTimeout(resolve, ms);
  });
}

function productNoteState(productId) {
  return state.notes[productId] || null;
}

function isSeller() {
  return state.user?.role === "seller";
}

function isBuyer() {
  return state.user?.role === "buyer";
}

function activeDraftLabel() {
  if (!state.activeDraftOrderId) {
    return "No active draft";
  }
  return `Draft ${state.activeDraftOrderId.slice(0, 8)}`;
}

function friendlyError(error, fallback) {
  if (error instanceof ApiError) {
    return error.payload?.error || error.message || fallback;
  }
  return error?.message || fallback;
}

function normalizeOrder(order) {
  if (!order) {
    return null;
  }

  return {
    ...order,
    items: Array.isArray(order.items) ? order.items : [],
  };
}

async function runAction(action, fallbackMessage) {
  clearBanner();
  setPending(1);
  try {
    await action();
  } catch (error) {
    setBanner("error", friendlyError(error, fallbackMessage));
  } finally {
    setPending(-1);
  }
}

async function initializeApp() {
  try {
    const [health, storefront, me, brands] = await Promise.all([
      api("/api/health", { expected: [200] }),
      api("/api/storefront", { expected: [200] }),
      api("/api/me", { expected: [200, 401] }),
      api("/api/brands", { expected: [200] }),
    ]);

    state.health = health.payload;
    state.storefront = storefront.payload;
    state.user = me.status === 200 ? me.payload.buyer : null;
    state.brands = brands.payload.brands || [];
  } catch (error) {
    state.health = { status: "error" };
    setBanner("error", friendlyError(error, "Failed to bootstrap storefront"));
  } finally {
    state.booting = false;
    render();
  }

  if (state.user) {
    hydratePrivateState().catch((error) => {
      setBanner("error", friendlyError(error, "Private account data is temporarily unavailable."));
    });
  }
}

async function hydratePrivateState() {
  if (!state.user) {
    state.orders = [];
    state.selectedOrder = null;
    state.selectedOrderId = null;
    state.activeDraftOrderId = null;
    return;
  }

  await Promise.all([
    isBuyer() ? loadOrders() : Promise.resolve(),
    loadBrands(),
  ]);
}

async function loadStorefront() {
  const response = await api("/api/storefront", { expected: [200] });
  state.storefront = response.payload;
}

async function loadSession() {
  const response = await api("/api/me", { expected: [200, 401] });
  state.user = response.status === 200 ? response.payload.buyer : null;
}

async function loadBrands() {
  const response = await api("/api/brands", { expected: [200] });
  state.brands = response.payload.brands || [];
}

async function loadOrders(preferredOrderId = state.selectedOrderId) {
  if (!state.user) {
    state.orders = [];
    state.selectedOrder = null;
    state.selectedOrderId = null;
    state.activeDraftOrderId = null;
    return;
  }

  const response = await api("/api/orders", { expected: [200] });
  const orders = response.payload.orders || [];
  state.orders = orders;
  state.activeDraftOrderId = orders.find((order) => order.status === "draft")?.public_id || null;

  if (preferredOrderId && orders.some((order) => order.public_id === preferredOrderId)) {
    await loadOrderDetail(preferredOrderId);
    return;
  }

  if (orders.length > 0) {
    const candidate = state.activeDraftOrderId || orders[0].public_id;
    await loadOrderDetail(candidate);
    return;
  }

  state.selectedOrderId = null;
  state.selectedOrder = null;
}

async function loadOrderDetail(orderId) {
  if (!orderId) {
    state.selectedOrderId = null;
    state.selectedOrder = null;
    return;
  }

  state.ui.loadingOrder = true;
  render();
  try {
    const response = await api(`/api/orders/${orderId}`, { expected: [200] });
    state.selectedOrderId = orderId;
    state.selectedOrder = normalizeOrder(response.payload.order);
    if (state.selectedOrder.status === "draft") {
      state.activeDraftOrderId = state.selectedOrder.public_id;
    }
  } finally {
    state.ui.loadingOrder = false;
    render();
  }
}

async function handleLogin(form) {
  const name = form.elements.namedItem("name")?.value.trim();
  const password = form.elements.namedItem("password")?.value || "";

  if (!name || !password) {
    setBanner("error", "Login requires both name and password.");
    return;
  }

  await runAction(async () => {
    await api("/api/login", {
      method: "POST",
      body: { name, password },
      expected: [200],
    });
    clearCachedValues(["login-name", "login-password"]);
    await loadSession();
    await hydratePrivateState();
    setBanner("success", `Welcome back, ${name}.`);
  }, "Unable to login");
}

async function handleRegister(form) {
  const name = form.elements.namedItem("name")?.value.trim();
  const password = form.elements.namedItem("password")?.value || "";
  const role = form.elements.namedItem("role")?.value || "buyer";

  if (!name || !password) {
    setBanner("error", "Register requires both name and password.");
    return;
  }

  await runAction(async () => {
    const body = { name, password, role };
    if (role === "buyer") {
      body.status = "beginner";
    }

    await api("/api/register", {
      method: "POST",
      body,
      expected: [201],
    });
    await api("/api/login", {
      method: "POST",
      body: { name, password },
      expected: [200],
    });
    clearCachedValues(["register-name", "register-password"]);
    await loadSession();
    await hydratePrivateState();
    setBanner("success", `Account ${name} is ready as a ${role}.`);
  }, "Unable to register");
}

async function handleLogout() {
  await runAction(async () => {
    await api("/api/logout", {
      method: "POST",
      body: {},
      expected: [200],
    });
    state.user = null;
    state.orders = [];
    state.selectedOrder = null;
    state.selectedOrderId = null;
    state.activeDraftOrderId = null;
    state.notes = {};
    state.wheelResult = null;
    render();
    setBanner("success", "Session closed.");
  }, "Unable to logout");
}

async function handleWheelSpin() {
  await runAction(async () => {
    state.ui.spinningWheel = true;
    render();
    const [response] = await Promise.all([
      api("/api/wheel/spin", {
        method: "POST",
        body: {},
        expected: [200],
      }),
      delay(1800),
    ]);
    state.wheelResult = response.payload;
    await loadSession();
    render();
    setBanner("success", `Wheel finished with ${response.payload.discount_percent}% discount.`);
  }, "Unable to spin the wheel");
  state.ui.spinningWheel = false;
  render();
}

async function createDraftOrder() {
  await runAction(async () => {
    const response = await api("/api/orders", {
      method: "POST",
      body: {},
      expected: [201],
    });
    const createdOrder = normalizeOrder(response.payload.order);
    const orderId = createdOrder.public_id;
    await loadOrders(orderId);
    setBanner("success", `Draft order ${orderId.slice(0, 8)} created.`);
  }, "Unable to create order");
}

async function addProductToOrder(productId, forceNewOrder) {
  if (!state.user) {
    setBanner("error", "Sign in to add products to an order.");
    return;
  }

  const busyKey = String(productId);
  state.ui.productBusy[busyKey] = true;
  render();

  try {
    let orderId = null;
    if (!forceNewOrder) {
      if (state.selectedOrder?.status === "draft") {
        orderId = state.selectedOrder.public_id;
      } else if (state.activeDraftOrderId) {
        orderId = state.activeDraftOrderId;
      }
    }
    if (!orderId) {
      const created = await api("/api/orders", {
        method: "POST",
        body: {},
        expected: [201],
      });
      orderId = normalizeOrder(created.payload.order).public_id;
    }

    const response = await api(`/api/orders/${orderId}/items`, {
      method: "POST",
      body: { product_id: productId, quantity: 1 },
      expected: [200],
    });
    const finalOrderId = normalizeOrder(response.payload.order).public_id;
    await loadOrders(finalOrderId);
    setBanner("success", `Product ${productId} was added to order ${finalOrderId.slice(0, 8)}.`);
  } catch (error) {
    setBanner("error", friendlyError(error, "Unable to add product to order"));
  } finally {
    delete state.ui.productBusy[busyKey];
    render();
  }
}

async function applyPromocode(form) {
  if (!state.selectedOrderId) {
    setBanner("error", "Select a draft order first.");
    return;
  }

  const code = form.elements.namedItem("code")?.value.trim();
  if (!code) {
    setBanner("error", "Promocode cannot be empty.");
    return;
  }

  await runAction(async () => {
    await api(`/api/orders/${state.selectedOrderId}/apply-promocode`, {
      method: "POST",
      body: { code },
      expected: [200],
    });
    clearCachedValues(["order-promocode"]);
    await loadSession();
    await loadOrders(state.selectedOrderId);
    setBanner("success", "Promocode applied.");
  }, "Unable to apply promocode");
}

async function checkoutSelectedOrder() {
  if (!state.selectedOrderId) {
    setBanner("error", "Select a draft order first.");
    return;
  }

  await runAction(async () => {
    await api(`/api/orders/${state.selectedOrderId}/checkout`, {
      method: "POST",
      body: {},
      expected: [200],
    });
    await loadSession();
    await loadOrders(state.selectedOrderId);
    setBanner("success", "Order completed.");
  }, "Unable to checkout order");
}

async function openNotes(productId) {
  state.notes[productId] = { status: "loading" };
  render();

  try {
    const response = await api(`/api/products/${productId}/notes`, {
      expected: [200, 403, 404],
    });
    if (response.status === 200) {
      state.notes[productId] = { status: "ready", data: response.payload.notes };
    } else {
      state.notes[productId] = {
        status: "locked",
        message: response.payload?.error || "Notes are locked.",
      };
    }
  } catch (error) {
    state.notes[productId] = {
      status: "error",
      message: friendlyError(error, "Unable to load notes"),
    };
  }

  render();
}

async function handleCreateProduct(form) {
  const brandId = Number(form.elements.namedItem("brand_id")?.value || 0);
  const title = form.elements.namedItem("title")?.value.trim();
  const shortDescription = form.elements.namedItem("short_description")?.value.trim();
  const price = Number(form.elements.namedItem("price")?.value || 0);

  if (!brandId || !title || !shortDescription || Number.isNaN(price) || price < 0) {
    setBanner("error", "Product form is incomplete.");
    return;
  }

  await runAction(async () => {
    const response = await api("/api/products", {
      method: "POST",
      body: {
        brand_id: brandId,
        title,
        short_description: shortDescription,
        price,
      },
      expected: [201],
    });
    state.seller.lastCreatedProductId = String(response.payload.product.id);
    clearCachedValues(["product-title", "product-short", "product-price"]);
    state.formCache["description-product-id"] = state.seller.lastCreatedProductId;
    await Promise.all([loadStorefront(), loadBrands()]);
    render();
    setBanner("success", `Product ${response.payload.product.id} listed. Add private notes next.`);
  }, "Unable to create product");
}

async function handleCreateDescription(form) {
  const productId = Number(form.elements.namedItem("product_id")?.value || 0);
  const description = form.elements.namedItem("description")?.value.trim();
  const top = form.elements.namedItem("top")?.value.trim();
  const middle = form.elements.namedItem("middle")?.value.trim();
  const base = form.elements.namedItem("base")?.value.trim();

  if (!productId || !description || !top || !middle || !base) {
    setBanner("error", "All note fields are required.");
    return;
  }

  await runAction(async () => {
    await api(`/api/products/${productId}/description`, {
      method: "POST",
      body: { description, top, middle, base },
      expected: [201],
    });
    clearCachedValues(["description-description", "description-top", "description-middle", "description-base"]);
    await Promise.all([loadStorefront(), loadBrands()]);
    render();
    setBanner("success", `Private notes for product ${productId} saved.`);
  }, "Unable to create description");
}

function renderBanner() {
  if (!state.ui.banner) {
    return "";
  }

  return `
    <div class="banner banner-${escapeHtml(state.ui.banner.type)}">
      <span>${escapeHtml(state.ui.banner.text)}</span>
      <button type="button" class="ghost-button compact-button" onclick="window.silverPearAction(event, 'dismiss-banner')">Dismiss</button>
    </div>
  `;
}

function renderHealthChip() {
  const status = state.health?.status || "offline";
  return `
    <div class="tiny-chip tiny-chip-${escapeHtml(status)}">
      <span class="tiny-chip-dot"></span>
      <span>${escapeHtml(status)}</span>
    </div>
  `;
}

function renderTopbar() {
  const saleEndsAt = state.storefront.sale_ends_at;
  return `
    <header class="topbar">
      <div class="brand-lockup">
        <p class="eyebrow">Silver Pear</p>
        <h1>A fragrance exchange for buyers and independent sellers.</h1>
        <p class="hero-copy">
          Fixed brand houses, seller-created listings, buyer-only orders, private notes, risky discounts, and one clock that refuses to slow down.
        </p>
      </div>

      <div class="hero-panels">
        <article class="hero-panel countdown-panel">
          <p class="panel-label">Seasonal offer ends in</p>
          <div class="countdown" data-sale-countdown>${escapeHtml(formatCountdown(saleEndsAt))}</div>
          <p class="panel-subtext">Exact cutoff: <span data-sale-exact>${escapeHtml(formatDate(saleEndsAt))}</span></p>
        </article>

        <article class="hero-panel stats-panel">
          <div class="panel-stack">
            <span class="panel-label">Backend status</span>
            ${renderHealthChip()}
          </div>
          <div class="panel-stack">
            <span class="panel-label">Catalog brands</span>
            <strong>${escapeHtml(state.storefront.brands.length)}</strong>
          </div>
          <div class="panel-stack">
            <span class="panel-label">Session</span>
            <strong>${state.user ? escapeHtml(state.user.name) : "guest"}</strong>
          </div>
        </article>
      </div>
    </header>
  `;
}

function renderAuthForms() {
  return `
    <div class="card-stack">
      <section class="panel">
        <div class="panel-head">
        <div>
          <p class="eyebrow">Sign in</p>
          <h2>Return to your account</h2>
          </div>
        </div>
        <form class="form-grid" onsubmit="window.silverPearSubmit(event, 'login')">
          <label class="field">
            <span>Name</span>
            <input name="name" data-persist="login-name" value="${escapeHtml(getCachedValue("login-name"))}" autocomplete="username" />
          </label>
          <label class="field">
            <span>Password</span>
            <input type="password" name="password" data-persist="login-password" value="${escapeHtml(getCachedValue("login-password"))}" autocomplete="current-password" />
          </label>
          <button type="submit" class="primary-button">Login</button>
        </form>
      </section>

      <section class="panel">
        <div class="panel-head">
          <div>
            <p class="eyebrow">Register</p>
            <h2>Create a marketplace account</h2>
          </div>
        </div>
        <form class="form-grid" onsubmit="window.silverPearSubmit(event, 'register')">
          <label class="field">
            <span>Name</span>
            <input name="name" data-persist="register-name" value="${escapeHtml(getCachedValue("register-name"))}" autocomplete="username" />
          </label>
          <label class="field">
            <span>Password</span>
            <input type="password" name="password" data-persist="register-password" value="${escapeHtml(getCachedValue("register-password"))}" autocomplete="new-password" />
          </label>
          <label class="field">
            <span>Role</span>
            <select name="role" data-persist="register-role">
              ${["buyer", "seller"].map((role) => `
                <option value="${role}" ${getCachedValue("register-role", "buyer") === role ? "selected" : ""}>${role}</option>
              `).join("")}
            </select>
          </label>
          <button type="submit" class="primary-button">Register</button>
        </form>
      </section>
    </div>
  `;
}

function renderProfile() {
  if (!state.user) {
    return renderAuthForms();
  }

  return `
    <section class="panel">
      <div class="panel-head">
        <div>
          <p class="eyebrow">Profile</p>
          <h2>${escapeHtml(state.user.name)}</h2>
        </div>
        <button type="button" class="ghost-button" onclick="window.silverPearAction(event, 'logout')">Logout</button>
      </div>

      <div class="profile-grid">
        <article class="metric-card">
          <span>Status</span>
          <strong>${escapeHtml(state.user.status)}</strong>
        </article>
        <article class="metric-card">
          <span>Balance</span>
          <strong>${escapeHtml(formatPrice(state.user.balance))}</strong>
        </article>
        <article class="metric-card">
          <span>Total spent</span>
          <strong>${escapeHtml(formatPrice(state.user.total_spent))}</strong>
        </article>
        <article class="metric-card">
          <span>Next discount</span>
          <strong>${escapeHtml(state.user.next_order_discount)}%</strong>
        </article>
      </div>

      <div class="detail-block">
        <span class="detail-label">Role</span>
        <strong>${escapeHtml(state.user.role)}</strong>
      </div>
      <div class="detail-block">
        <span class="detail-label">Created</span>
        <strong>${escapeHtml(formatDate(state.user.created_at))}</strong>
      </div>
    </section>
  `;
}

function renderWheel() {
  if (!state.user) {
    return `
      <section class="panel">
        <div class="panel-head">
          <div>
            <p class="eyebrow">Wheel</p>
            <h2>Lucky spin</h2>
          </div>
        </div>
        <p class="muted-copy">Register or login to unlock your one personal spin.</p>
      </section>
    `;
  }

  if (!isBuyer()) {
    return `
      <section class="panel">
        <div class="panel-head">
          <div>
            <p class="eyebrow">Seller tools</p>
            <h2>Discount wheel is buyer-only</h2>
          </div>
        </div>
        <p class="muted-copy">Sellers publish products to the exchange. Buyers unlock discounts and purchases.</p>
      </section>
    `;
  }

  const used = Boolean(state.user.wheel_used);
  const result = state.wheelResult;
  const spinning = Boolean(state.ui.spinningWheel);

  return `
    <section class="panel">
      <div class="panel-head">
        <div>
          <p class="eyebrow">Wheel</p>
          <h2>Lucky discount spin</h2>
        </div>
        <button type="button" class="primary-button" onclick="window.silverPearAction(event, 'spin-wheel')" ${(used || spinning) ? "disabled" : ""}>
          ${used ? "Already used" : spinning ? "Spinning..." : "Spin now"}
        </button>
      </div>

      <div class="wheel-stage">
        <div class="wheel-orbit ${spinning ? "wheel-orbit-spinning" : ""}">
          <div class="wheel-core">
            <span>5%</span>
            <span>10%</span>
            <span>15%</span>
            <span>20%</span>
            <strong>100%</strong>
          </div>
        </div>
      </div>

      <p class="muted-copy">
        Every buyer gets one wheel attempt. Codes are entered manually during draft checkout.
      </p>

      ${result ? `
        <div class="result-card ${result.is_jackpot ? "result-jackpot" : ""}">
          <p class="result-title">${escapeHtml(result.outcome)}</p>
          <strong>${escapeHtml(result.discount_percent)}%</strong>
          <code>${escapeHtml(result.code)}</code>
        </div>
      ` : `
        <div class="soft-note">No spin result captured in this session yet.</div>
      `}
    </section>
  `;
}

function renderOrderSummary(order) {
  const selected = state.selectedOrderId === order.public_id;
  return `
    <button type="button" class="order-tile ${selected ? "order-tile-selected" : ""}" onclick="window.silverPearAction(event, 'select-order', '${escapeHtml(order.public_id)}')">
      <div class="order-tile-row">
        <strong>${escapeHtml(order.public_id.slice(0, 8))}</strong>
        <span class="status-pill status-${escapeHtml(order.status)}">${escapeHtml(order.status)}</span>
      </div>
      <div class="order-tile-row">
        <span>${escapeHtml(formatPrice(order.final_price))}</span>
        <span>${escapeHtml(formatDate(order.created_at))}</span>
      </div>
    </button>
  `;
}

function renderSelectedOrder() {
  if (!state.user) {
    return `
      <section class="panel">
        <div class="panel-head">
          <div>
            <p class="eyebrow">Orders</p>
            <h2>Drafts and purchases</h2>
          </div>
        </div>
        <p class="muted-copy">Login to create a draft order and unlock private notes after purchase.</p>
      </section>
    `;
  }

  if (!isBuyer()) {
    return `
      <section class="panel">
        <div class="panel-head">
          <div>
            <p class="eyebrow">Orders</p>
            <h2>Buyer desk only</h2>
          </div>
        </div>
        <p class="muted-copy">Sign in as a buyer to open drafts, purchase products, and unlock private notes.</p>
      </section>
    `;
  }

  const detail = state.selectedOrder;
  const detailItems = Array.isArray(detail?.items) ? detail.items : [];

  return `
    <section class="panel">
      <div class="panel-head">
        <div>
          <p class="eyebrow">Orders</p>
          <h2>Drafts and purchases</h2>
        </div>
        <div class="button-row">
          <button type="button" class="ghost-button compact-button" onclick="window.silverPearAction(event, 'refresh-orders')">Refresh</button>
          <button type="button" class="primary-button compact-button" onclick="window.silverPearAction(event, 'create-order')">Create draft</button>
        </div>
      </div>

      <div class="soft-note">
        Active draft: <strong>${escapeHtml(activeDraftLabel())}</strong>
      </div>

      ${state.orders.length === 0 ? `
        <div class="empty-state">No orders yet. Pick a product from the catalog to start one.</div>
      ` : `
        <div class="order-list">
          ${state.orders.map(renderOrderSummary).join("")}
        </div>
      `}

      <div class="order-detail">
        ${state.ui.loadingOrder ? `
          <div class="empty-state">Loading selected order...</div>
        ` : detail ? `
          <div class="detail-header">
            <div>
              <p class="detail-label">Order ID</p>
              <h3>${escapeHtml(detail.public_id)}</h3>
            </div>
            <span class="status-pill status-${escapeHtml(detail.status)}">${escapeHtml(detail.status)}</span>
          </div>

          <div class="detail-grid">
            <article class="metric-card">
              <span>Total</span>
              <strong>${escapeHtml(formatPrice(detail.total_price))}</strong>
            </article>
            <article class="metric-card">
              <span>Final</span>
              <strong>${escapeHtml(formatPrice(detail.final_price))}</strong>
            </article>
            <article class="metric-card">
              <span>Created</span>
              <strong>${escapeHtml(formatDate(detail.created_at))}</strong>
            </article>
            <article class="metric-card">
              <span>Completed</span>
              <strong>${escapeHtml(formatDate(detail.completed_at))}</strong>
            </article>
          </div>

          ${detail.promocode ? `
            <div class="soft-note">
              Applied promocode: <code>${escapeHtml(detail.promocode.code)}</code> for ${escapeHtml(detail.promocode.discount_percent)}%
            </div>
          ` : ""}

          <div class="item-list">
            ${detailItems.length === 0 ? `
              <div class="empty-state">This draft is empty. Add a product from the catalog to continue.</div>
            ` : detailItems.map((item) => `
              <article class="order-item-card">
                <div class="order-item-main">
                  <strong>${escapeHtml(item.title)}</strong>
                  <span>Product #${escapeHtml(item.product_id)}</span>
                  <span>Quantity: ${escapeHtml(item.quantity)}</span>
                  <span>${escapeHtml(formatPrice(item.unit_price))}</span>
                </div>
                <button type="button" class="ghost-button compact-button" onclick="window.silverPearAction(event, 'open-notes', '${escapeHtml(item.product_id)}')">
                  Open notes
                </button>
              </article>
            `).join("")}
          </div>

          ${detail.status === "draft" ? `
            <div class="draft-actions">
              <form class="promo-form" onsubmit="window.silverPearSubmit(event, 'apply-promocode')">
                <label class="field">
                  <span>Promocode</span>
                  <input name="code" data-persist="order-promocode" value="${escapeHtml(getCachedValue("order-promocode"))}" placeholder="Enter manual code" />
                </label>
                <button type="submit" class="ghost-button">Apply code</button>
              </form>
              <button type="button" class="primary-button" onclick="window.silverPearAction(event, 'checkout-order')">Checkout draft</button>
            </div>
          ` : ""}
        ` : `
          <div class="empty-state">Select an order to inspect items and pricing.</div>
        `}
      </div>
    </section>
  `;
}

function renderNotesBlock(productId) {
  const noteState = productNoteState(productId);
  if (!noteState) {
    return "";
  }

  if (noteState.status === "loading") {
    return `<div class="note-shell note-loading">Loading private notes...</div>`;
  }

  if (noteState.status === "locked") {
    return `<div class="note-shell note-locked">${escapeHtml(noteState.message)}</div>`;
  }

  if (noteState.status === "error") {
    return `<div class="note-shell note-error">${escapeHtml(noteState.message)}</div>`;
  }

  const notes = noteState.data;
  return `
    <div class="note-shell note-ready">
      <p class="note-description">${escapeHtml(notes.description)}</p>
      <div class="note-grid">
        <div><span>Top</span><strong>${escapeHtml(notes.top)}</strong></div>
        <div><span>Middle</span><strong>${escapeHtml(notes.middle)}</strong></div>
        <div><span>Base</span><strong>${escapeHtml(notes.base)}</strong></div>
      </div>
    </div>
  `;
}

function renderProductActions(product) {
  if (!state.user) {
    return `
      <div class="product-actions">
        <button type="button" class="ghost-button" onclick="window.silverPearAction(event, 'focus-auth')">Login to trade</button>
      </div>
    `;
  }

  if (!isBuyer()) {
    return `
      <div class="product-actions">
        <button type="button" class="ghost-button" onclick="window.silverPearAction(event, 'focus-auth')">Buyer account required to purchase</button>
      </div>
    `;
  }

  const busy = Boolean(state.ui.productBusy[String(product.id)]);
  return `
    <div class="product-actions">
      <button type="button" class="primary-button" onclick="window.silverPearAction(event, 'add-product-active', '${escapeHtml(product.id)}')" ${busy ? "disabled" : ""}>
        ${busy ? "Adding..." : state.activeDraftOrderId ? "Add to active draft" : "Create draft + add"}
      </button>
      <button type="button" class="ghost-button" onclick="window.silverPearAction(event, 'add-product-new', '${escapeHtml(product.id)}')" ${busy ? "disabled" : ""}>
        New order from this scent
      </button>
      <button type="button" class="ghost-button" onclick="window.silverPearAction(event, 'open-notes', '${escapeHtml(product.id)}')">
        Open private notes
      </button>
    </div>
  `;
}

function renderCatalog() {
  const brands = state.storefront.brands || [];
  return `
    <section class="catalog-shell">
      <div class="section-head">
        <div>
          <p class="eyebrow">Catalog</p>
          <h2>All public products, grouped by brand</h2>
        </div>
        <button type="button" class="ghost-button compact-button" onclick="window.silverPearAction(event, 'refresh-storefront')">Refresh catalog</button>
      </div>

      ${brands.length === 0 ? `
        <div class="empty-state">No brands are visible in the storefront yet.</div>
      ` : `
        <div class="brand-list">
          ${brands.map((brand) => `
            <article class="brand-panel">
              <div class="brand-head">
                <div>
                  <p class="eyebrow">Brand</p>
                  <h3>${escapeHtml(brand.name)}</h3>
                </div>
                <span class="brand-count">${escapeHtml(brand.products.length)} items</span>
              </div>

              ${brand.products.length === 0 ? `
                <div class="empty-inline">No active perfumes in this line yet.</div>
              ` : `
                <div class="product-grid">
                  ${brand.products.map((product) => `
                    <article class="product-card">
                      <div class="product-topline">
                        <span class="product-id">#${escapeHtml(product.id)}</span>
                        <span class="price-tag">${escapeHtml(formatPrice(product.price))}</span>
                      </div>
                      <h4>${escapeHtml(product.title)}</h4>
                      <p class="product-copy">${escapeHtml(product.short_description)}</p>
                      ${renderProductActions(product)}
                      ${renderNotesBlock(product.id)}
                    </article>
                  `).join("")}
                </div>
              `}
            </article>
          `).join("")}
        </div>
      `}
    </section>
  `;
}

function renderSellerStudio() {
  if (!isSeller()) {
    return "";
  }

  return `
    <section class="panel admin-panel">
      <div class="panel-head">
        <div>
          <p class="eyebrow">Seller studio</p>
          <h2>List products on the fragrance exchange</h2>
        </div>
        <button type="button" class="ghost-button compact-button" onclick="window.silverPearAction(event, 'refresh-brands')">Refresh brands</button>
      </div>

      <div class="admin-brands">
        ${(state.brands || []).map((brand) => `<span class="tag-chip">#${escapeHtml(brand.id)} ${escapeHtml(brand.name)}</span>`).join("") || '<span class="muted-copy">No brands loaded.</span>'}
      </div>

      <div class="admin-grid">
        <form class="panel form-panel" onsubmit="window.silverPearSubmit(event, 'create-product')">
          <div class="panel-head compact-head">
            <div>
              <p class="eyebrow">Step 1</p>
              <h3>Create product</h3>
            </div>
          </div>
          <label class="field">
            <span>Brand</span>
            <select name="brand_id" data-persist="product-brand-id">
              <option value="">Choose brand</option>
              ${(state.brands || []).map((brand) => `
                <option value="${escapeHtml(brand.id)}" ${String(getCachedValue("product-brand-id")) === String(brand.id) ? "selected" : ""}>
                  #${escapeHtml(brand.id)} ${escapeHtml(brand.name)}
                </option>
              `).join("")}
            </select>
          </label>
          <label class="field">
            <span>Title</span>
            <input name="title" data-persist="product-title" value="${escapeHtml(getCachedValue("product-title"))}" placeholder="Ashen Citrus" />
          </label>
          <label class="field">
            <span>Short description</span>
            <textarea name="short_description" data-persist="product-short" placeholder="Dry citrus perfume with cold mineral undertones.">${escapeHtml(getCachedValue("product-short"))}</textarea>
          </label>
          <label class="field">
            <span>Price</span>
            <input name="price" type="number" min="0" data-persist="product-price" value="${escapeHtml(getCachedValue("product-price", "12500"))}" />
          </label>
          <button type="submit" class="primary-button">Create product</button>
        </form>

        <form class="panel form-panel" onsubmit="window.silverPearSubmit(event, 'create-description')">
          <div class="panel-head compact-head">
            <div>
              <p class="eyebrow">Step 2</p>
              <h3>Create private notes</h3>
            </div>
          </div>
          <label class="field">
            <span>Product ID</span>
            <input name="product_id" type="number" min="1" data-persist="description-product-id" value="${escapeHtml(getCachedValue("description-product-id", state.seller.lastCreatedProductId))}" />
          </label>
          <label class="field">
            <span>Description</span>
            <textarea name="description" data-persist="description-description" placeholder="A layered perfume that opens bright and ends on a heavy dark accord.">${escapeHtml(getCachedValue("description-description"))}</textarea>
          </label>
          <label class="field">
            <span>Top notes</span>
            <input name="top" data-persist="description-top" value="${escapeHtml(getCachedValue("description-top"))}" placeholder="bergamot, grapefruit zest" />
          </label>
          <label class="field">
            <span>Middle notes</span>
            <input name="middle" data-persist="description-middle" value="${escapeHtml(getCachedValue("description-middle"))}" placeholder="iris, violet leaf" />
          </label>
          <label class="field">
            <span>Base notes</span>
            <input name="base" data-persist="description-base" value="${escapeHtml(getCachedValue("description-base"))}" placeholder="cedar, warm amber" />
          </label>
          <button type="submit" class="primary-button">Save notes</button>
        </form>
      </div>
    </section>
  `;
}

function renderShell() {
  return `
    <div class="app-shell">
      <div class="backdrop backdrop-left"></div>
      <div class="backdrop backdrop-right"></div>
      ${renderBanner()}
      ${renderTopbar()}

      <div class="layout-grid">
        <main class="main-column">
          ${renderCatalog()}
          ${renderSellerStudio()}
        </main>

        <aside class="sidebar-column" id="auth-anchor">
          ${renderProfile()}
          ${renderWheel()}
          ${renderSelectedOrder()}
        </aside>
      </div>
    </div>
  `;
}

function render() {
  if (state.booting) {
    root.innerHTML = `
      <div class="loading-screen">
        <div class="loading-card">
          <p class="eyebrow">Silver Pear</p>
          <h1>Ink is warming up...</h1>
          <p class="muted-copy">The perfume desk opens in a moment.</p>
        </div>
      </div>
    `;
    return;
  }

  root.innerHTML = renderShell();
  updateCountdownTargets();
}

function updateCountdownTargets() {
  const countdown = formatCountdown(state.storefront.sale_ends_at);
  const exact = formatDate(state.storefront.sale_ends_at);

  for (const element of document.querySelectorAll("[data-sale-countdown]")) {
    element.textContent = countdown;
  }

  for (const element of document.querySelectorAll("[data-sale-exact]")) {
    element.textContent = exact;
  }
}

root.addEventListener("input", (event) => {
  const target = event.target;
  if (!(target instanceof HTMLInputElement || target instanceof HTMLTextAreaElement || target instanceof HTMLSelectElement)) {
    return;
  }
  storeInputValue(target);
});

root.addEventListener("change", (event) => {
  const target = event.target;
  if (!(target instanceof HTMLInputElement || target instanceof HTMLTextAreaElement || target instanceof HTMLSelectElement)) {
    return;
  }
  storeInputValue(target);
});

window.silverPearSubmit = async function silverPearSubmit(event, formName) {
  event.preventDefault();
  const form = event.currentTarget;
  if (!(form instanceof HTMLFormElement)) {
    return;
  }

  switch (formName) {
    case "login":
      await handleLogin(form);
      break;
    case "register":
      await handleRegister(form);
      break;
    case "apply-promocode":
      await applyPromocode(form);
      break;
    case "create-product":
      await handleCreateProduct(form);
      break;
    case "create-description":
      await handleCreateDescription(form);
      break;
    default:
      break;
  }
};

window.silverPearAction = async function silverPearAction(event, action, value = "") {
  event.preventDefault();

  switch (action) {
    case "dismiss-banner":
      clearBanner();
      render();
      break;
    case "logout":
      await handleLogout();
      break;
    case "spin-wheel":
      await handleWheelSpin();
      break;
    case "create-order":
      await createDraftOrder();
      break;
    case "refresh-orders":
      await runAction(async () => {
        await loadOrders();
        setBanner("success", "Orders refreshed.");
      }, "Unable to refresh orders");
      break;
    case "select-order":
      await runAction(async () => {
        await loadOrderDetail(value);
      }, "Unable to load order");
      break;
    case "checkout-order":
      await checkoutSelectedOrder();
      break;
    case "add-product-active":
      await addProductToOrder(Number(value || 0), false);
      break;
    case "add-product-new":
      await addProductToOrder(Number(value || 0), true);
      break;
    case "open-notes":
      await openNotes(Number(value || 0));
      break;
    case "refresh-storefront":
      await runAction(async () => {
        await loadStorefront();
        render();
      }, "Unable to refresh storefront");
      break;
    case "refresh-brands":
      await runAction(async () => {
        await loadBrands();
        render();
      }, "Unable to refresh brands");
      break;
    case "focus-auth":
      document.getElementById("auth-anchor")?.scrollIntoView({ behavior: "smooth", block: "start" });
      break;
    default:
      break;
  }
};

window.setInterval(updateCountdownTargets, 1000);
initializeApp();
