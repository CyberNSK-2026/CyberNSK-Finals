class ApiError extends Error {
  constructor(message, status, data) {
    super(message);
    this.name = "ApiError";
    this.status = status;
    this.data = data;
  }
}

async function api(path, method = "GET", body) {
  const res = await fetch(path, {
    method,
    credentials: "same-origin",
    headers: body ? { "Content-Type": "application/json" } : undefined,
    body: body ? JSON.stringify(body) : undefined,
  });

  const text = await res.text();
  let data = text;
  try {
    data = text ? JSON.parse(text) : null;
  } catch {
    // keep text payload
  }

  if (res.status === 401) {
    const next = encodeURIComponent(`${location.pathname}${location.search}`);
    location.href = `/login?next=${next}`;
    throw new ApiError("Session expired. Please sign in again.", 401, data);
  }

  if (!res.ok) {
    const message =
      data && typeof data === "object" && "error" in data
        ? String(data.error)
        : typeof data === "string"
          ? data
          : "Request failed";
    throw new ApiError(message, res.status, data);
  }

  return data;
}

function byId(id) {
  return document.getElementById(id);
}

function valueOf(id) {
  const node = byId(id);
  return node ? node.value : "";
}

function setValue(id, value) {
  const node = byId(id);
  if (node) {
    node.value = value ?? "";
  }
}

function setText(id, value) {
  const node = byId(id);
  if (node) {
    node.textContent = value ?? "";
  }
}

function pretty(payload) {
  return typeof payload === "string" ? payload : JSON.stringify(payload, null, 2);
}

function out(id, payload, type = "success") {
  const node = byId(id);
  if (!node) return;
  node.hidden = false;
  node.classList.remove("is-error", "is-success", "is-info");
  node.classList.add(`is-${type}`);
  node.textContent = pretty(payload);
}

function clearOut(id) {
  const node = byId(id);
  if (!node) return;
  node.hidden = true;
  node.textContent = "";
  node.classList.remove("is-error", "is-success", "is-info");
}

function fieldError(inputId, message) {
  const node = byId(inputId);
  if (node) {
    node.focus();
    node.setAttribute("aria-invalid", "true");
  }
  throw new Error(message);
}

function clearFieldState(...ids) {
  ids.forEach((id) => {
    const node = byId(id);
    if (node) {
      node.removeAttribute("aria-invalid");
    }
  });
}

function positiveInt(inputId, label) {
  const raw = String(valueOf(inputId)).trim();
  const n = Number(raw);
  if (!raw || !Number.isInteger(n) || n <= 0) {
    fieldError(inputId, `${label} must be a positive number.`);
  }
  return n;
}

function requiredText(inputId, label) {
  const value = String(valueOf(inputId)).trim();
  if (!value) {
    fieldError(inputId, `${label} is required.`);
  }
  return value;
}

function storageKey(key) {
  return `vipgames:${location.pathname}:${key}`;
}

function remember(key, value) {
  if (value !== undefined && value !== null && value !== "") {
    sessionStorage.setItem(storageKey(key), String(value));
  }
}

function recall(key) {
  return sessionStorage.getItem(storageKey(key));
}

function restoreValue(inputId, key) {
  const current = valueOf(inputId);
  const saved = recall(key);
  if (!current && saved) {
    setValue(inputId, saved);
  }
}

function setBusy(trigger, busy) {
  if (!trigger) return;
  trigger.disabled = busy;
  if (busy) {
    trigger.dataset.originalText = trigger.textContent;
    trigger.textContent = "Working...";
    trigger.setAttribute("aria-busy", "true");
  } else {
    trigger.textContent = trigger.dataset.originalText || trigger.textContent;
    trigger.removeAttribute("aria-busy");
  }
}

async function runAction(trigger, outputId, action) {
  clearOut(outputId);
  setBusy(trigger, true);
  try {
    clearFieldState(...Array.from(document.querySelectorAll("[aria-invalid='true']")).map((node) => node.id));
    const data = await action();
    out(outputId, data, "success");
    return data;
  } catch (e) {
    if (!(e instanceof ApiError && e.status === 401)) {
      out(outputId, e.message || "Unexpected error", "error");
    }
    return null;
  } finally {
    setBusy(trigger, false);
  }
}

function submitter(event) {
  event.preventDefault();
  return event.submitter || event.currentTarget.querySelector("button[type='submit']");
}

async function vipRegister(event) {
  const button = submitter(event);
  await runAction(button, "auth-message", async () => {
    const username = requiredText("register-username", "Username");
    const password = requiredText("register-password", "Password");
    await api("/api/auth/register", "POST", { username, password });
    location.href = "/portal";
    return { ok: true };
  });
}

async function vipLogin(event) {
  const button = submitter(event);
  await runAction(button, "auth-message", async () => {
    const username = requiredText("login-username", "Username");
    const password = requiredText("login-password", "Password");
    await api("/api/auth/login", "POST", { username, password });
    const params = new URLSearchParams(location.search);
    location.href = params.get("next") || "/portal";
    return { ok: true };
  });
}

async function vipLogout(button) {
  await runAction(button, "global-message", async () => {
    await api("/api/auth/logout", "POST");
    location.href = "/";
    return { ok: true };
  });
}

async function createPuzzleBoard(button) {
  await runAction(button, "puzzle-out", async () => {
    const title = requiredText("puzzle-title", "Board title");
    const data = await api("/api/games/puzzle/boards", "POST", { title });
    setValue("puzzle-id", data.id);
    setText("puzzle-current-id", data.id);
    remember("boardId", data.id);
    return {
      message: "Board created. Add a solved layer payload next.",
      ...data,
    };
  });
}

async function savePuzzleStego(button) {
  await runAction(button, "puzzle-out", async () => {
    const id = positiveInt("puzzle-id", "Board ID");
    const payload = requiredText("puzzle-payload", "Solved layer payload");
    const data = await api(`/api/games/puzzle/${id}/save-stego`, "POST", { payload });
    remember("boardId", id);
    return {
      message: "Solved layer saved. You can preview the board now.",
      ...data,
    };
  });
}

async function loadPuzzlePreview(button) {
  await runAction(button, "puzzle-out", async () => {
    const id = positiveInt("puzzle-id", "Board ID");
    remember("boardId", id);
    return api(`/api/games/puzzle/${id}/preview?mode=solved`);
  });
}

async function createPet(button) {
  await runAction(button, "pet-out", async () => {
    const name = requiredText("pet-name", "Pet name");
    const tag = requiredText("pet-tag", "Pet tag");
    const data = await api("/api/games/petfarm/pets", "POST", { name, tag });
    setValue("target-pet-id", data.id);
    setText("pet-current-id", data.id);
    remember("petId", data.id);
    return {
      message: "Pet created. Create a booster or load the pet state.",
      ...data,
    };
  });
}

async function createBooster(button) {
  await runAction(button, "pet-out", async () => {
    const payload = requiredText("booster-payload", "Booster payload");
    const data = await api("/api/games/petfarm/boosters", "POST", { payload });
    setValue("booster-id", data.id);
    setText("booster-current-id", data.id);
    remember("boosterId", data.id);
    return {
      message: "Booster created. Apply it to the selected pet next.",
      ...data,
    };
  });
}

async function applyBooster(button) {
  await runAction(button, "pet-out", async () => {
    const boosterId = positiveInt("booster-id", "Booster ID");
    const petId = positiveInt("target-pet-id", "Pet ID");
    const data = await api("/api/games/petfarm/boosters/apply", "POST", { boosterId, petId });
    remember("boosterId", boosterId);
    remember("petId", petId);
    return {
      message: "Booster applied. Load the pet to inspect the new state.",
      ...data,
    };
  });
}

async function loadPet(button) {
  await runAction(button, "pet-out", async () => {
    const id = positiveInt("target-pet-id", "Pet ID");
    remember("petId", id);
    return api(`/api/games/petfarm/pets/${id}`);
  });
}

async function createAlchemyRun(button) {
  await runAction(button, "alchemy-out", async () => {
    const recipe = requiredText("alchemy-recipe", "Recipe");
    const data = await api("/api/games/alchemy/runs", "POST", { recipe });
    setValue("alchemy-run-id", data.id);
    setText("alchemy-current-id", data.id);
    remember("runId", data.id);
    return {
      message: "Run created. Finalize an artifact note next.",
      ...data,
    };
  });
}

async function finalizeAlchemy(button) {
  await runAction(button, "alchemy-out", async () => {
    const id = positiveInt("alchemy-run-id", "Run ID");
    const artifactNote = requiredText("alchemy-note", "Artifact note");
    const data = await api(`/api/games/alchemy/runs/${id}/finalize`, "POST", { artifactNote });
    remember("runId", id);
    return {
      message: "Artifact finalized. Load it to inspect the result.",
      ...data,
    };
  });
}

async function loadAlchemyArtifact(button) {
  await runAction(button, "alchemy-out", async () => {
    const id = positiveInt("alchemy-run-id", "Run ID");
    remember("runId", id);
    return api(`/api/games/alchemy/runs/${id}/artifact`);
  });
}

async function createCard(button) {
  await runAction(button, "cards-out", async () => {
    const customName = requiredText("card-name", "Card name");
    const power = Number(valueOf("card-power"));
    if (!Number.isFinite(power)) {
      fieldError("card-power", "Power must be a number.");
    }
    const data = await api("/api/games/cards", "POST", { customName, power });
    setValue("card-id", data.id);
    setValue("trade-card", data.id);
    setText("card-current-id", data.id);
    remember("cardId", data.id);
    return {
      message: "Card created. You can load it or use it in a trade.",
      ...data,
    };
  });
}

async function loadCard(button) {
  await runAction(button, "cards-out", async () => {
    const id = positiveInt("card-id", "Card ID");
    remember("cardId", id);
    return api(`/api/games/cards/${id}`);
  });
}

async function createTrade(button) {
  await runAction(button, "cards-out", async () => {
    const toUserId = positiveInt("trade-user", "Recipient user ID");
    const cardId = positiveInt("trade-card", "Trade card ID");
    const data = await api("/api/games/cards/trades", "POST", { toUserId, cardId });
    setValue("trade-id", data.id);
    setText("trade-current-id", data.id);
    remember("tradeId", data.id);
    remember("cardId", cardId);
    return {
      message: "Trade created. Share the trade ID with the recipient.",
      ...data,
    };
  });
}

async function acceptTrade(button) {
  await runAction(button, "cards-out", async () => {
    const id = positiveInt("trade-id", "Trade ID");
    const data = await api(`/api/games/cards/trades/${id}/accept`, "POST");
    remember("tradeId", id);
    return {
      message: "Trade accepted.",
      ...data,
    };
  });
}

async function lookupAchievement(button) {
  await runAction(button, "ach-out", async () => {
    const username = requiredText("ach-username", "Username");
    const code = requiredText("ach-code", "Achievement code");
    return api(`/api/achievements/board/${encodeURIComponent(username)}/details?code=${encodeURIComponent(code)}`);
  });
}

function restorePageState() {
  restoreValue("puzzle-id", "boardId");
  restoreValue("target-pet-id", "petId");
  restoreValue("booster-id", "boosterId");
  restoreValue("alchemy-run-id", "runId");
  restoreValue("card-id", "cardId");
  restoreValue("trade-card", "cardId");
  restoreValue("trade-id", "tradeId");

  setText("puzzle-current-id", valueOf("puzzle-id") || "none");
  setText("pet-current-id", valueOf("target-pet-id") || "none");
  setText("booster-current-id", valueOf("booster-id") || "none");
  setText("alchemy-current-id", valueOf("alchemy-run-id") || "none");
  setText("card-current-id", valueOf("card-id") || "none");
  setText("trade-current-id", valueOf("trade-id") || "none");
}

document.addEventListener("DOMContentLoaded", restorePageState);

window.vipRegister = vipRegister;
window.vipLogin = vipLogin;
window.vipLogout = vipLogout;
window.createPuzzleBoard = createPuzzleBoard;
window.savePuzzleStego = savePuzzleStego;
window.loadPuzzlePreview = loadPuzzlePreview;
window.createPet = createPet;
window.createBooster = createBooster;
window.applyBooster = applyBooster;
window.loadPet = loadPet;
window.createAlchemyRun = createAlchemyRun;
window.finalizeAlchemy = finalizeAlchemy;
window.loadAlchemyArtifact = loadAlchemyArtifact;
window.createCard = createCard;
window.loadCard = loadCard;
window.createTrade = createTrade;
window.acceptTrade = acceptTrade;
window.lookupAchievement = lookupAchievement;
