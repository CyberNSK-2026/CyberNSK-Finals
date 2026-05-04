(function () {
    const navUserGroup = document.getElementById("nav-user-group");
    const navUserButton = document.getElementById("nav-user-button");
    const navLoginButton = document.getElementById("nav-login-button");
    const checkSessionButton = document.getElementById("check-session-btn");
    const logoutButton = document.getElementById("logout-btn");
    const sessionModalElement = document.getElementById("sessionCheckModal");
    const sessionSuccess = document.getElementById("session-check-success");
    const sessionValid = document.getElementById("session-check-valid");
    const sessionError = document.getElementById("session-check-error");

    const listResult = document.getElementById("list-result");
    const userProfile = document.getElementById("user-profile");
    const profileUsername = document.getElementById("profile-username");
    const profileUserid = document.getElementById("profile-userid");
    const profileLastLogin = document.getElementById("profile-last-login");
    const checklistsSection = document.getElementById("user-checklists-section");
    const checklistsList = document.getElementById("user-checklists-list");

    if (
        !navUserGroup || !navUserButton || !navLoginButton || !checkSessionButton || !logoutButton || !sessionModalElement ||
        !sessionSuccess || !sessionValid || !sessionError ||
        !listResult || !userProfile || !profileUsername || !profileUserid || !profileLastLogin ||
        !checklistsSection || !checklistsList
    ) {
        return;
    }

    const sessionModal = new bootstrap.Modal(sessionModalElement);

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
     * @returns {{username?: string, userID?: number} | null}
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
     * @returns {number | null}
     */
    function parseUserIdFromUrl() {
        const params = new URLSearchParams(window.location.search);
        const raw = (params.get("userid") || params.get("id") || "").trim();
        if (!raw || !/^\d+$/.test(raw)) {
            return null;
        }
        const n = parseInt(raw, 10);
        if (!Number.isFinite(n) || n <= 0) {
            return null;
        }
        return n;
    }

    /**
     * @param {*} item
     * @returns {void}
     */
    function appendChecklistCard(item) {
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
            "<div class=\"col\"><p>Created By: <a href=\"user.html?id=" + encodeURIComponent(ownerId) + "\">" + ownerUsername + "</a></p></div>" +
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
        checklistsList.appendChild(container);
    }

    /**
     * @param {number} userId
     * @returns {Promise<void>}
     */
    async function loadUserPage(userId) {
        showListStatus("", true);
        userProfile.hidden = true;
        checklistsSection.hidden = true;
        checklistsList.innerHTML = "";

        const userRes = await window.CheckD.config.apiCall(
            "/users/get?userid=" + encodeURIComponent(String(userId)),
            { method: "GET" }
        );
        const listRes = await window.CheckD.config.apiCall(
            "/checklists/list-by-user?userid=" + encodeURIComponent(String(userId)),
            { method: "GET" }
        );

        if (!userRes.ok || !userRes.data) {
            const err = userRes.data && userRes.data.error ? String(userRes.data.error) : userRes.errorCode || "failed_to_load_user";
            if (userRes.status === 401) {
                showListStatus("Please log in to view user profiles.", false);
            } else if (userRes.status === 404) {
                const msg = userRes.data && userRes.data.error ? String(userRes.data.error) : "User not found";
                showListStatus(msg, false);
            } else if (userRes.status === 400) {
                showListStatus("Invalid user id: " + err, false);
            } else {
                showListStatus("Failed to load user: " + err, false);
            }
            return;
        }

        if (userRes.data.ok !== true) {
            const err = userRes.data.error ? String(userRes.data.error) : "failed_to_load_user";
            showListStatus(err, false);
            return;
        }

        profileUsername.textContent = userRes.data.username ? String(userRes.data.username) : "—";
        profileUserid.textContent = String(userId);
        profileLastLogin.textContent = userRes.data.last_login ? String(userRes.data.last_login) : "n/a";
        userProfile.hidden = false;

        if (!listRes.ok || !listRes.data) {
            const err = listRes.data && listRes.data.error ? String(listRes.data.error) : listRes.errorCode || "failed_to_load_lists";
            showListStatus("User loaded, but checklists failed: " + err, false);
            checklistsSection.hidden = false;
            return;
        }

        if (listRes.data.ok === false) {
            const err = listRes.data.error ? String(listRes.data.error) : "failed_to_load_lists";
            showListStatus("User loaded, but checklists: " + err, false);
            checklistsSection.hidden = false;
            return;
        }

        const rawResults = Array.isArray(listRes.data.results) ? listRes.data.results : [];
        checklistsSection.hidden = false;
        if (rawResults.length === 0) {
            const empty = document.createElement("p");
            empty.className = "text-muted";
            empty.textContent = "No public checklists from this user.";
            checklistsList.appendChild(empty);
        } else {
            for (let i = 0; i < rawResults.length; i += 1) {
                appendChecklistCard(rawResults[i]);
            }
            const openButtons = checklistsList.querySelectorAll(".open-checklist-btn");
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
        }
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
        sessionSuccess.textContent = result.ok ? "yes" : "no";
        sessionValid.textContent = result.sessionValid ? "yes" : "no";
        sessionError.textContent = result.error === null ? "null" : result.error;
        sessionModal.show();
    });

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

    const userId = parseUserIdFromUrl();
    if (userId === null) {
        showListStatus("Missing or invalid user id. Use ?userid=123 or ?id=123 in the URL.", false);
        return;
    }

    loadUserPage(userId);
})();
