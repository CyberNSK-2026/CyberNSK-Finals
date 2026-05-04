(function () {
    /** @type {number} */
    let currentPage = 1;
    /** @type {number} */
    let totalPages = 1;

    /**
     * @param {string} tokenPart
     * @returns {string}
     */
    function normalizeBase64(tokenPart) {
        let normalized = tokenPart.replace(/-/g, "+").replace(/_/g, "/");
        const missingPadding = normalized.length % 4;
        if (missingPadding > 0) {
            normalized += "=".repeat(4 - missingPadding);
        }
        return normalized;
    }

    /**
     * @param {string} token
     * @returns {{username?: string, userID?: number, userRole?: number, expires?: string} | null}
     */
    function parseSessionFromToken(token) {
        if (!token || token.indexOf(".") < 0) {
            return null;
        }

        const parts = token.split(".");
        if (!parts[0]) {
            return null;
        }

        try {
            const payload = atob(normalizeBase64(parts[0]));
            return JSON.parse(payload);
        } catch (error) {
            return null;
        }
    }

    /**
     * @returns {Promise<{ok: boolean, sessionValid: boolean, error: string | null}>}
     */
    async function checkSession() {
        const result = await window.CheckD.config.apiCall("/auth/check_session", { method: "GET" });

        if (!result.ok || !result.data || result.data.ok !== true) {
            return {
                ok: false,
                sessionValid: false,
                error: result.data && result.data.error ? String(result.data.error) : result.errorCode || "unknown_error",
            };
        }

        return {
            ok: true,
            sessionValid: result.data.session_valid === true,
            error: null,
        };
    }

    /**
     * @param {string} message
     * @param {boolean} isSuccess
     * @returns {void}
     */
    function showListStatus(message, isSuccess) {
        const resultBox = document.getElementById("list-result");
        if (!resultBox) {
            return;
        }
        resultBox.innerHTML = "";
        if (!message) {
            return;
        }
        const alert = document.createElement("div");
        alert.className = "alert " + (isSuccess ? "alert-success" : "alert-danger") + " container mt-3";
        alert.textContent = message;
        resultBox.appendChild(alert);
    }

    /**
     * @param {number} page
     * @returns {Promise<void>}
     */
    async function loadChecklistPage(page) {
        const listContainer = document.getElementById("checklists-list");
        const pageCurrent = document.getElementById("page-current");
        const prevButton = document.getElementById("page-prev");
        const nextButton = document.getElementById("page-next");

        if (!listContainer || !pageCurrent || !prevButton || !nextButton) {
            return;
        }

        showListStatus("", true);
        const response = await window.CheckD.config.apiCall("/checklists/list?page=" + page, { method: "GET" });

        if (!response.ok || !response.data) {
            listContainer.innerHTML = "";
            const errorText = response.data && response.data.error ? String(response.data.error) : response.errorCode || "failed_to_load";
            showListStatus("Failed to load checklists: " + errorText, false);
            return;
        }

        const rawResults = Array.isArray(response.data.results) ? response.data.results : [];
        const pagination = response.data.pagination || {};
        currentPage = typeof pagination.current === "number" ? pagination.current : page;
        totalPages = typeof pagination.pages === "number" && pagination.pages > 0 ? pagination.pages : 1;
        pageCurrent.textContent = String(currentPage) + " / " + String(totalPages);
        prevButton.disabled = currentPage <= 1;
        nextButton.disabled = currentPage >= totalPages;

        listContainer.innerHTML = "";
        if (rawResults.length === 0) {
            showListStatus("No checklists available on this page.", false);
            return;
        }

        for (let i = 0; i < rawResults.length; i += 1) {
            const item = rawResults[i];
            const questionCount = typeof item.questions === "number"
                ? item.questions
                : Array.isArray(item.questions) ? item.questions.length : 0;
            const timesCompleted = typeof item.times_completed === "number" ? item.times_completed : 0;
            const createdAt = item.created_at ? String(item.created_at) : "n/a";
            const checklistId = item.id !== undefined && item.id !== null ? String(item.id) : "";
            const checklistTitle = item.title
                ? String(item.title)
                : (item.name ? String(item.name) : ("Checklist #" + checklistId));
            const ownerId = item.owner && item.owner.id !== undefined && item.owner.id !== null
                ? String(item.owner.id)
                : "n/a";
            const ownerUsername = item.owner && item.owner.username
                ? String(item.owner.username)
                : ("User #" + ownerId);
            const container = document.createElement("div");
            container.className = "container";
            container.style.marginTop = "1em";
            container.innerHTML = "" +
                "<div class=\"checklist-row\">" +
                "<h4>" + checklistTitle + "</h4>" +
                "<div class=\"row\">" +
                "<div class=\"col\"><p>Questions: " + String(questionCount) + "</p></div>" +
                "<div class=\"col\"><p>Created By: <a href=\"/user.html?id=" + encodeURIComponent(ownerId) + "\">" + ownerUsername + "</a></p></div>" +
                "</div>" +
                "<div class=\"row\">" +
                "<div class=\"col\"><p>Times completed: " + String(timesCompleted) + "</p></div>" +
                "<div class=\"col\"><p>Created at: " + createdAt + "</p></div>" +
                "</div>" +
                "<div>" +
                "<h5>Description</h5>" +
                "<p>" + String(item.description || "") + "</p>" +
                "</div>" +
                "<button class=\"btn btn-primary btn-sm open-checklist-btn\" type=\"button\" data-checklist-id=\"" + checklistId + "\">Open</button>" +
                "</div>";
            listContainer.appendChild(container);
        }

        const openButtons = listContainer.querySelectorAll(".open-checklist-btn");
        for (let i = 0; i < openButtons.length; i += 1) {
            openButtons[i].addEventListener("click", function (event) {
                const target = event.currentTarget;
                if (!(target instanceof HTMLButtonElement)) {
                    return;
                }
                const checklistId = target.dataset.checklistId;
                if (!checklistId) {
                    return;
                }
                window.location.href = "complete.html?id=" + encodeURIComponent(checklistId);
            });
        }

        const url = new URL(window.location.href);
        url.searchParams.set("page", String(currentPage));
        window.history.replaceState({}, "", url.toString());
    }

    const userGroup = document.getElementById("nav-user-group");
    const userButton = document.getElementById("nav-user-button");
    const loginButton = document.getElementById("nav-login-button");
    const checkSessionButton = document.getElementById("check-session-btn");
    const logoutButton = document.getElementById("logout-btn");
    const modalElement = document.getElementById("sessionCheckModal");
    const prevButton = document.getElementById("page-prev");
    const nextButton = document.getElementById("page-next");

    if (!userGroup || !userButton || !loginButton || !checkSessionButton || !logoutButton || !modalElement || !prevButton || !nextButton) {
        return;
    }

    const modal = new bootstrap.Modal(modalElement);
    const successEl = document.getElementById("session-check-success");
    const validEl = document.getElementById("session-check-valid");
    const errorEl = document.getElementById("session-check-error");

    loginButton.addEventListener("click", function () {
        window.location.href = "login.html";
    });
    logoutButton.addEventListener("click", function () {
        window.CheckD.config.storage.clearAuth();
        window.location.href = "login.html";
    });

    const authToken = window.CheckD.config.storage.get(window.CheckD.config.STORAGE_KEYS.authToken, "");
    const sessionData = parseSessionFromToken(String(authToken || ""));

    if (sessionData && sessionData.username) {
        userButton.textContent = sessionData.username;
        userGroup.hidden = false;
        loginButton.hidden = true;
    } else {
        userGroup.hidden = true;
        loginButton.hidden = false;
    }

    checkSessionButton.addEventListener("click", async function () {
        const result = await checkSession();

        if (successEl) {
            successEl.textContent = result.ok ? "yes" : "no";
        }
        if (validEl) {
            validEl.textContent = result.sessionValid ? "yes" : "no";
        }
        if (errorEl) {
            errorEl.textContent = result.error === null ? "null" : result.error;
        }

        modal.show();
    });

    prevButton.addEventListener("click", function () {
        if (currentPage <= 1) {
            return;
        }
        loadChecklistPage(currentPage - 1);
    });

    nextButton.addEventListener("click", function () {
        if (currentPage >= totalPages) {
            return;
        }
        loadChecklistPage(currentPage + 1);
    });

    const params = new URLSearchParams(window.location.search);
    const pageFromUrl = Number(params.get("page") || "1");
    const safeStartPage = Number.isNaN(pageFromUrl) || pageFromUrl <= 0 ? 1 : pageFromUrl;
    loadChecklistPage(safeStartPage);
})();
