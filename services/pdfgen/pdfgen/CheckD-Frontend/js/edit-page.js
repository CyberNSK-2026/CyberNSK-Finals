(function () {
    /**
     * @typedef {Object} SessionPayload
     * @property {string=} username
     */

    const navUserGroup = document.getElementById("nav-user-group");
    const navUserButton = document.getElementById("nav-user-button");
    const navLoginButton = document.getElementById("nav-login-button");
    const checkSessionButton = document.getElementById("check-session-btn");
    const logoutButton = document.getElementById("logout-btn");

    const clNameInput = document.getElementById("cl-name");
    const clDescInput = document.getElementById("cl-desc");
    const createChecklistButton = document.getElementById("create-checklist-btn");
    const publicButton = document.getElementById("b-a");
    const privateButton = document.getElementById("b-b");
    const visibleButton = document.getElementById("b-c");
    const hiddenButton = document.getElementById("b-d");
    const createModalElement = document.getElementById("createChecklistModal");
    const createModalError = document.getElementById("create-modal-error");

    const sessionModalElement = document.getElementById("sessionCheckModal");
    const sessionSuccess = document.getElementById("session-check-success");
    const sessionValid = document.getElementById("session-check-valid");
    const sessionError = document.getElementById("session-check-error");
    const listResult = document.getElementById("list-result");
    const listContainer = document.getElementById("checklists-list");
    const pagePrev = document.getElementById("page-prev");
    const pageNext = document.getElementById("page-next");
    const pageCurrent = document.getElementById("page-current");

    if (
        !navUserGroup || !navUserButton || !navLoginButton || !checkSessionButton || !logoutButton ||
        !clNameInput || !clDescInput || !createChecklistButton || !publicButton || !privateButton || !visibleButton || !hiddenButton ||
        !createModalElement || !createModalError || !sessionModalElement ||
        !listResult || !listContainer || !pagePrev || !pageNext || !pageCurrent
    ) {
        return;
    }

    /** @type {boolean} */
    let isPublic = true;
    /** @type {boolean} */
    let isHidden = false;
    /** @type {number} */
    let currentPage = 1;
    /** @type {number} */
    let totalPages = 1;

    const createModal = new bootstrap.Modal(createModalElement);
    const sessionModal = new bootstrap.Modal(sessionModalElement);

    /**
     * @param {string} message
     * @returns {void}
     */
    function showCreateModalError(message) {
        createModalError.innerHTML = "";
        if (!message) {
            return;
        }
        const alert = document.createElement("div");
        alert.className = "alert alert-danger mt-3 mb-0";
        alert.textContent = message;
        createModalError.appendChild(alert);
    }

    /**
     * @param {boolean} condition
     * @param {HTMLButtonElement} activeButton
     * @param {HTMLButtonElement} inactiveButton
     * @returns {void}
     */
    function setToggleState(condition, activeButton, inactiveButton) {
        if (condition) {
            activeButton.classList.add("btn-primary");
            activeButton.classList.remove("btn-light");
            inactiveButton.classList.add("btn-light");
            inactiveButton.classList.remove("btn-primary");
            return;
        }
        inactiveButton.classList.add("btn-primary");
        inactiveButton.classList.remove("btn-light");
        activeButton.classList.add("btn-light");
        activeButton.classList.remove("btn-primary");
    }

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
     * @returns {SessionPayload | null}
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
        listResult.innerHTML = "";
        if (!message) {
            return;
        }
        const alert = document.createElement("div");
        alert.className = "alert " + (isSuccess ? "alert-success" : "alert-danger") + " container mt-3";
        alert.textContent = message;
        listResult.appendChild(alert);
    }

    /**
     * @returns {void}
     */
    function bindEditButtons() {
        const editButtons = document.querySelectorAll(".open-editor-btn");
        for (let i = 0; i < editButtons.length; i += 1) {
            editButtons[i].addEventListener("click", function (event) {
                const target = event.currentTarget;
                if (!(target instanceof HTMLButtonElement)) {
                    return;
                }
                const checklistId = target.dataset.checklistId;
                if (!checklistId) {
                    return;
                }
                window.location.href = "create.html?mode=edit&id=" + encodeURIComponent(checklistId);
            });
        }

        const openButtons = document.querySelectorAll(".open-checklist-btn");
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

        const deleteButtons = document.querySelectorAll(".delete-checklist-btn");
        for (let i = 0; i < deleteButtons.length; i += 1) {
            deleteButtons[i].addEventListener("click", async function (event) {
                const target = event.currentTarget;
                if (!(target instanceof HTMLButtonElement)) {
                    return;
                }
                const checklistId = target.dataset.checklistId;
                if (!checklistId) {
                    return;
                }
                if (!window.confirm("Delete checklist #" + checklistId + " and all its questions and answers? This cannot be undone.")) {
                    return;
                }
                const res = await window.CheckD.config.apiCall(
                    "/checklists/delete?id=" + encodeURIComponent(checklistId),
                    { method: "DELETE" }
                );
                if (res.ok && res.data && res.data.ok === true) {
                    await loadEditableList(currentPage);
                    showListStatus("Checklist deleted.", true);
                    return;
                }
                const err = res.data && res.data.error !== undefined && res.data.error !== null
                    ? String(res.data.error)
                    : (res.errorCode || "delete_failed");
                showListStatus("Delete failed: " + err, false);
            });
        }
    }

    /**
     * @param {number} page
     * @returns {Promise<void>}
     */
    async function loadEditableList(page) {
        showListStatus("", true);
        const result = await window.CheckD.config.apiCall("/checklists/editable-list?page=" + page, { method: "GET" });

        if (!result.ok || !result.data) {
            listContainer.innerHTML = "";
            const errorText = result.data && result.data.error ? String(result.data.error) : result.errorCode || "failed_to_load";
            showListStatus("Failed to load editable checklists: " + errorText, false);
            return;
        }

        const rows = Array.isArray(result.data.results) ? result.data.results : [];
        const pagination = result.data.pagination || {};
        currentPage = typeof pagination.current === "number" ? pagination.current : page;
        totalPages = typeof pagination.pages === "number" && pagination.pages > 0 ? pagination.pages : 1;
        pageCurrent.textContent = String(currentPage) + " / " + String(totalPages);
        pagePrev.disabled = currentPage <= 1;
        pageNext.disabled = currentPage >= totalPages;

        listContainer.innerHTML = "";
        if (rows.length === 0) {
            showListStatus("No editable checklists on this page.", false);
            return;
        }

        for (let i = 0; i < rows.length; i += 1) {
            const item = rows[i];
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
                "<button class=\"btn btn-primary btn-sm me-2 open-checklist-btn\" type=\"button\" data-checklist-id=\"" + checklistId + "\">Open</button>" +
                "<button class=\"btn btn-primary btn-sm me-2 open-editor-btn\" type=\"button\" data-checklist-id=\"" + checklistId + "\">Edit</button>" +
                "<button class=\"btn btn-danger btn-sm delete-checklist-btn\" type=\"button\" data-checklist-id=\"" + checklistId + "\">Delete</button>" +
                "</div>";
            listContainer.appendChild(container);
        }

        bindEditButtons();
        const url = new URL(window.location.href);
        url.searchParams.set("page", String(currentPage));
        window.history.replaceState({}, "", url.toString());
    }

    const authToken = window.CheckD.config.storage.get(window.CheckD.config.STORAGE_KEYS.authToken, "");
    const sessionData = parseSessionFromToken(String(authToken || ""));
    if (sessionData && sessionData.username) {
        navUserButton.textContent = sessionData.username;
        navUserGroup.hidden = false;
        navLoginButton.hidden = true;
    } else {
        navUserGroup.hidden = true;
        navLoginButton.hidden = false;
    }

    navLoginButton.addEventListener("click", function () {
        window.location.href = "login.html";
    });
    logoutButton.addEventListener("click", function () {
        window.CheckD.config.storage.clearAuth();
        window.location.href = "login.html";
    });

    checkSessionButton.addEventListener("click", async function () {
        const result = await checkSession();
        if (sessionSuccess) {
            sessionSuccess.textContent = result.ok ? "yes" : "no";
        }
        if (sessionValid) {
            sessionValid.textContent = result.sessionValid ? "yes" : "no";
        }
        if (sessionError) {
            sessionError.textContent = result.error === null ? "null" : result.error;
        }
        sessionModal.show();
    });

    publicButton.addEventListener("click", function () {
        isPublic = true;
        setToggleState(true, publicButton, privateButton);
    });
    privateButton.addEventListener("click", function () {
        isPublic = false;
        setToggleState(false, publicButton, privateButton);
    });
    visibleButton.addEventListener("click", function () {
        isHidden = false;
        setToggleState(true, visibleButton, hiddenButton);
    });
    hiddenButton.addEventListener("click", function () {
        isHidden = true;
        setToggleState(false, visibleButton, hiddenButton);
    });

    createChecklistButton.addEventListener("click", function () {
        const name = clNameInput.value.trim();
        const description = clDescInput.value.trim();
        if (!name) {
            showCreateModalError("Checklist name is required.");
            return;
        }
        showCreateModalError("");

        window.CheckD.config.storage.set(window.CheckD.config.STORAGE_KEYS.editorBootstrap, {
            mode: "new",
            name: name,
            description: description,
            is_public: isPublic,
            is_hidden: isHidden,
        });

        createModal.hide();
        window.location.href = "create.html?mode=new";
    });

    createModalElement.addEventListener("show.bs.modal", function () {
        clNameInput.value = "";
        clDescInput.value = "";
        isPublic = true;
        isHidden = false;
        setToggleState(true, publicButton, privateButton);
        setToggleState(true, visibleButton, hiddenButton);
        showCreateModalError("");
    });

    pagePrev.addEventListener("click", function () {
        if (currentPage <= 1) {
            return;
        }
        loadEditableList(currentPage - 1);
    });

    pageNext.addEventListener("click", function () {
        if (currentPage >= totalPages) {
            return;
        }
        loadEditableList(currentPage + 1);
    });

    const params = new URLSearchParams(window.location.search);
    const pageFromUrl = Number(params.get("page") || "1");
    const startPage = Number.isNaN(pageFromUrl) || pageFromUrl <= 0 ? 1 : pageFromUrl;
    loadEditableList(startPage);
})();
