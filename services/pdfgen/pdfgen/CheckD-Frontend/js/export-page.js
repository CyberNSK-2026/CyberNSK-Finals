(function () {
    /** @type {number} */
    let currentPage = 1;
    /** @type {number} */
    let totalPages = 1;

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
    const listContainer = document.getElementById("answers-list");
    const pagePrev = document.getElementById("page-prev");
    const pageNext = document.getElementById("page-next");
    const pageCurrent = document.getElementById("page-current");

    if (
        !navUserGroup || !navUserButton || !navLoginButton || !checkSessionButton || !logoutButton || !sessionModalElement ||
        !sessionSuccess || !sessionValid || !sessionError ||
        !listResult || !listContainer || !pagePrev || !pageNext || !pageCurrent
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
     * @returns {{username?: string, userID?: number, user_id?: number, userRole?: number} | null}
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
     * @param {*} user
     * @returns {{id: string, label: string}}
     */
    function formatUserLink(user) {
        if (!user || typeof user !== "object") {
            return { id: "-1", label: "Unknown user" };
        }
        const rawId = user.user_id !== undefined && user.user_id !== null
            ? user.user_id
            : (user.userID !== undefined && user.userID !== null ? user.userID : -1);
        const id = String(rawId);
        const label = user.username ? String(user.username) : ("User #" + id);
        return { id: id, label: label };
    }

    /**
     * @param {*} checklist
     * @returns {{id: string, name: string}}
     */
    function formatChecklistLink(checklist) {
        if (!checklist || typeof checklist !== "object") {
            return {
                id: "-1",
                name: "Unknown checklist",
            };
        }
        const rawId = checklist.checklist_id !== undefined && checklist.checklist_id !== null
            ? checklist.checklist_id
            : (checklist.id !== undefined && checklist.id !== null ? checklist.id : -1);
        const id = String(rawId);
        const name = checklist.checklist_name ? String(checklist.checklist_name) : "Unknown checklist";
        return {
            id: id,
            name: name,
        };
    }

    /**
     * Checklist author (who created the checklist), not the person who submitted the answer.
     * @param {*} checklist
     * @returns {{id: string, label: string}}
     */
    function formatChecklistAuthorLink(checklist) {
        if (!checklist || typeof checklist !== "object") {
            return { id: "-1", label: "Unknown user" };
        }
        const by = checklist.checklist_by;
        if (!by || typeof by !== "object") {
            return { id: "-1", label: "Unknown user" };
        }
        const rawId = by.user_id !== undefined && by.user_id !== null
            ? by.user_id
            : (by.userID !== undefined && by.userID !== null ? by.userID : -1);
        const id = String(rawId);
        const nameField = by.user_name !== undefined && by.user_name !== null
            ? by.user_name
            : (by.username !== undefined && by.username !== null ? by.username : null);
        const label = nameField ? String(nameField) : ("User #" + id);
        return { id: id, label: label };
    }

    /**
     * @param {*} row
     * @returns {number}
     */
    function answerCompleterNumericId(row) {
        if (!row || !row.user || typeof row.user !== "object") {
            return NaN;
        }
        const u = row.user;
        const raw = u.user_id !== undefined && u.user_id !== null
            ? u.user_id
            : (u.userID !== undefined && u.userID !== null ? u.userID : undefined);
        if (raw === undefined || raw === null) {
            return NaN;
        }
        const n = Number(raw);
        return Number.isFinite(n) ? n : NaN;
    }

    /**
     * @param {*} session
     * @returns {number}
     */
    function sessionNumericUserId(session) {
        if (!session || typeof session !== "object") {
            return NaN;
        }
        const raw = session.userID !== undefined && session.userID !== null
            ? session.userID
            : (session.user_id !== undefined && session.user_id !== null ? session.user_id : undefined);
        if (raw === undefined || raw === null) {
            return NaN;
        }
        const n = Number(raw);
        return Number.isFinite(n) ? n : NaN;
    }

    /**
     * Absolute URL for a path returned by print-export (e.g. /pdf-files/name.pdf).
     * @param {string} path
     * @returns {string | null}
     */
    function absoluteUrlForApiPath(path) {
        if (!path || typeof path !== "string" || path.charAt(0) !== "/") {
            return null;
        }
        try {
            const base = window.CheckD.config.buildApiUrl("/");
            const origin = new URL(base).origin;
            return origin + path;
        } catch (e) {
            return null;
        }
    }

    /**
     * @param {number} page
     * @returns {Promise<void>}
     */
    async function loadExportPage(page) {
        showListStatus("", true);
        const response = await window.CheckD.config.apiCall("/checklists/export-list?page=" + page, { method: "GET" });

        if (!response.ok || !response.data || response.data.ok !== true) {
            listContainer.innerHTML = "";
            const errorText = response.data && response.data.error ? String(response.data.error) : response.errorCode || "failed_to_load";
            showListStatus("Failed to load export list: " + errorText, false);
            return;
        }

        const rows = Array.isArray(response.data.answers) ? response.data.answers : [];
        const pagination = response.data.pagination || {};
        currentPage = typeof pagination.current === "number" ? pagination.current : page;
        totalPages = typeof pagination.pages === "number" && pagination.pages > 0 ? pagination.pages : 1;
        pageCurrent.textContent = String(currentPage) + " / " + String(totalPages);
        pagePrev.disabled = currentPage <= 1;
        pageNext.disabled = currentPage >= totalPages;

        listContainer.innerHTML = "";
        if (rows.length === 0) {
            showListStatus("No export rows on this page.", false);
            return;
        }

        const sessionData = parseSessionFromToken(String(window.CheckD.config.storage.get(window.CheckD.config.STORAGE_KEYS.authToken, "") || ""));
        const role = sessionData && sessionData.userRole !== undefined && sessionData.userRole !== null
            ? Number(sessionData.userRole)
            : 0;
        const myUserId = sessionNumericUserId(sessionData);

        for (let i = 0; i < rows.length; i += 1) {
            const row = rows[i];
            const answerId = row && row.id !== undefined && row.id !== null ? String(row.id) : "";
            const completedAt = row && row.completed_at ? String(row.completed_at) : "n/a";

            const completer = formatUserLink(row.user);
            const author = formatChecklistAuthorLink(row.checklist);
            const cl = formatChecklistLink(row.checklist);
            const answerIdNum = parseInt(answerId, 10);
            const canPrintExport = !Number.isNaN(answerIdNum) && answerIdNum > 0;

            const container = document.createElement("div");
            container.className = "container";
            container.style.marginTop = "1em";

            // Backend: userRole 1 = admin, 2 = user. Export for 1/2. Delete for admin or if this answer was submitted by the current user.
            // print-export sends answer_id (row in checklist_answers), not raw checklist id.
            const exportBtn = (role === 1 || role === 2) && canPrintExport
                ? "<button type=\"button\" class=\"btn btn-primary btn-sm me-2 export-answer-btn\" data-answer-id=\"" + String(answerIdNum) + "\">Export</button>"
                : "";
            const completerId = answerCompleterNumericId(row);
            const isOwnAnswer = !Number.isNaN(myUserId) && !Number.isNaN(completerId) && myUserId === completerId;
            const deleteBtn = role === 1 || isOwnAnswer
                ? "<button type=\"button\" class=\"btn btn-danger btn-sm delete-answer-btn\" data-answer-id=\"" + answerId + "\">Delete</button>"
                : "";

            container.innerHTML = "" +
                "<div class=\"checklist-row\">" +
                "<h4>Answer #" + answerId + "</h4>" +
                "<div class=\"row g-3 align-items-start\">" +
                "<div class=\"col-md-6\">" +
                "<p class=\"mb-2 mb-md-3\">User: <a href=\"/user.html?id=" + encodeURIComponent(completer.id) + "\">" + completer.label + "</a></p>" +
                "<p class=\"mb-0 text-body-secondary\">Completed at: " + completedAt + "</p>" +
                "</div>" +
                "<div class=\"col-md-6\">" +
                "<p class=\"mb-2 mb-md-3\">Checklist: <a href=\"complete.html?id=" + encodeURIComponent(cl.id) + "\">" + cl.name + "</a></p>" +
                "<p class=\"mb-0\">Checklist author: <a href=\"/user.html?id=" + encodeURIComponent(author.id) + "\">" + author.label + "</a></p>" +
                "</div>" +
                "</div>" +
                "<div class=\"mt-3\">" + exportBtn + deleteBtn + "</div>" +
                "</div>";

            listContainer.appendChild(container);
        }

        const exportButtons = listContainer.querySelectorAll(".export-answer-btn");
        for (let i = 0; i < exportButtons.length; i += 1) {
            exportButtons[i].addEventListener("click", async function (event) {
                const target = event.currentTarget;
                if (!(target instanceof HTMLButtonElement)) {
                    return;
                }
                const answerIdRaw = target.dataset.answerId;
                const answerIdParsed = answerIdRaw ? parseInt(answerIdRaw, 10) : NaN;
                if (!Number.isFinite(answerIdParsed) || answerIdParsed <= 0) {
                    showListStatus("Invalid answer id for export.", false);
                    return;
                }
                target.disabled = true;
                const res = await window.CheckD.config.apiCall("/checklists/print-export", {
                    method: "POST",
                    body: { answer_id: answerIdParsed },
                });
                target.disabled = false;
                if (res.ok && res.data && res.data.ok === true && res.data.path) {
                    const pdfUrl = absoluteUrlForApiPath(String(res.data.path));
                    if (pdfUrl) {
                        window.open(pdfUrl, "_blank", "noopener,noreferrer");
                        showListStatus("PDF opened in a new tab.", true);
                    } else {
                        showListStatus("Export succeeded but PDF path is invalid.", false);
                    }
                    return;
                }
                const err = res.data && res.data.error !== undefined && res.data.error !== null
                    ? String(res.data.error)
                    : (res.data && res.data.reason ? String(res.data.reason) : (res.errorCode || "print_export_failed"));
                showListStatus("Export failed: " + err, false);
            });
        }

        const deleteButtons = listContainer.querySelectorAll(".delete-answer-btn");
        for (let i = 0; i < deleteButtons.length; i += 1) {
            deleteButtons[i].addEventListener("click", async function (event) {
                const target = event.currentTarget;
                if (!(target instanceof HTMLButtonElement)) {
                    return;
                }
                const id = target.dataset.answerId;
                if (!id) {
                    return;
                }
                if (!window.confirm("Delete answer #" + id + "? This cannot be undone.")) {
                    return;
                }
                const res = await window.CheckD.config.apiCall(
                    "/checklists/delete-answer?id=" + encodeURIComponent(id),
                    { method: "DELETE" }
                );
                if (res.ok && res.data && res.data.ok === true) {
                    await loadExportPage(currentPage);
                    showListStatus("Answer deleted.", true);
                    return;
                }
                const err = res.data && res.data.error !== undefined && res.data.error !== null
                    ? String(res.data.error)
                    : (res.errorCode || "delete_failed");
                showListStatus("Delete failed: " + err, false);
            });
        }

        const url = new URL(window.location.href);
        url.searchParams.set("page", String(currentPage));
        window.history.replaceState({}, "", url.toString());
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

    pagePrev.addEventListener("click", function () {
        if (currentPage <= 1) {
            return;
        }
        loadExportPage(currentPage - 1);
    });
    pageNext.addEventListener("click", function () {
        if (currentPage >= totalPages) {
            return;
        }
        loadExportPage(currentPage + 1);
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

    const params = new URLSearchParams(window.location.search);
    const pageFromUrl = Number(params.get("page") || "1");
    const startPage = Number.isNaN(pageFromUrl) || pageFromUrl <= 0 ? 1 : pageFromUrl;
    loadExportPage(startPage);
})();
