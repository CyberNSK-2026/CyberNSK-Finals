(function () {
    /** Backend paths (adjust if your routes differ). */
    var FILES_LIST = "/files/list";
    var FILES_NEW = "/files/new";
    var FILES_GET = "/files/get?id=";
    var FILES_DELETE = "/files/delete?id=";

    var navUserGroup = document.getElementById("nav-user-group");
    var navUserButton = document.getElementById("nav-user-button");
    var navLoginButton = document.getElementById("nav-login-button");
    var checkSessionButton = document.getElementById("check-session-btn");
    var logoutButton = document.getElementById("logout-btn");
    var sessionModalElement = document.getElementById("sessionCheckModal");
    var sessionSuccess = document.getElementById("session-check-success");
    var sessionValid = document.getElementById("session-check-valid");
    var sessionError = document.getElementById("session-check-error");
    var listResult = document.getElementById("list-result");
    var filesTbody = document.getElementById("files-tbody");
    var uploadModalElement = document.getElementById("uploadFileModal");
    var fileUploadInput = document.getElementById("file-upload-input");
    var uploadFilenameInput = document.getElementById("upload-filename");
    var uploadModalError = document.getElementById("upload-modal-error");
    var confirmUploadBtn = document.getElementById("confirm-upload-btn");

    if (
        !navUserGroup || !navUserButton || !navLoginButton || !checkSessionButton || !logoutButton || !sessionModalElement ||
        !sessionSuccess || !sessionValid || !sessionError || !listResult || !filesTbody ||
        !uploadModalElement || !fileUploadInput || !uploadFilenameInput || !uploadModalError || !confirmUploadBtn ||
        !window.CheckD || !window.CheckD.config
    ) {
        return;
    }

    var sessionModal = new bootstrap.Modal(sessionModalElement);
    var uploadModal = new bootstrap.Modal(uploadModalElement);

    /**
     * @param {string} tokenPart
     * @returns {string}
     */
    function normalizeBase64(tokenPart) {
        var normalized = tokenPart.replace(/-/g, "+").replace(/_/g, "/");
        var missingPadding = normalized.length % 4;
        if (missingPadding > 0) {
            normalized += "=".repeat(4 - missingPadding);
        }
        return normalized;
    }

    /**
     * @param {string} token
     * @returns {{username?: string, userID?: number, userRole?: number} | null}
     */
    function parseSessionFromToken(token) {
        if (!token || token.indexOf(".") < 0) {
            return null;
        }
        var parts = token.split(".");
        if (!parts[0]) {
            return null;
        }
        try {
            var payload = atob(normalizeBase64(parts[0]));
            return JSON.parse(payload);
        } catch (error) {
            return null;
        }
    }

    /**
     * @returns {Promise<{ok: boolean, sessionValid: boolean, error: string | null}>}
     */
    async function checkSession() {
        var result = await window.CheckD.config.apiCall("/auth/check_session", { method: "GET" });
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
        var alert = document.createElement("div");
        alert.className = "alert " + (isSuccess ? "alert-success" : "alert-danger") + " container mt-3";
        alert.textContent = message;
        listResult.appendChild(alert);
    }

    /**
     * @param {string} message
     * @returns {void}
     */
    function showUploadModalError(message) {
        uploadModalError.innerHTML = "";
        if (!message) {
            return;
        }
        var alert = document.createElement("div");
        alert.className = "alert alert-danger mt-2 mb-0";
        alert.textContent = message;
        uploadModalError.appendChild(alert);
    }

    /**
     * @param {*} n
     * @returns {string}
     */
    function formatFileSize(n) {
        if (n === undefined || n === null || n === "") {
            return "—";
        }
        var b = Number(n);
        if (!Number.isFinite(b) || b < 0) {
            return "—";
        }
        var units = ["B", "KB", "MB", "GB"];
        var u = 0;
        while (b >= 1024 && u < units.length - 1) {
            b /= 1024;
            u += 1;
        }
        var s = u === 0 ? String(Math.round(b)) : b.toFixed(b < 10 && u > 0 ? 2 : 1);
        return s + " " + units[u];
    }

    /**
     * @param {File} file
     * @returns {Promise<string>}
     */
    function fileToBase64(file) {
        return new Promise(function (resolve, reject) {
            var reader = new FileReader();
            reader.onload = function () {
                var r = reader.result;
                if (typeof r !== "string") {
                    reject(new Error("read_failed"));
                    return;
                }
                var i = r.indexOf(",");
                resolve(i >= 0 ? r.slice(i + 1) : r);
            };
            reader.onerror = function () {
                reject(reader.error || new Error("read_failed"));
            };
            reader.readAsDataURL(file);
        });
    }

    /**
     * JSON: { ok, error?, filedata: base64 }. Builds a blob and opens it in a new tab.
     * @param {number} fileId
     * @returns {Promise<{ok: boolean, error?: string}>}
     */
    async function openFileDownload(fileId) {
        var res = await window.CheckD.config.apiCall(FILES_GET + encodeURIComponent(String(fileId)), { method: "GET" });
        if (!res.ok || !res.data) {
            var err0 = res.data && res.data.error ? String(res.data.error) : (res.errorCode || "request_failed");
            return { ok: false, error: err0 };
        }
        if (res.data.ok !== true || res.data.filedata === undefined || res.data.filedata === null) {
            var msg = res.data.error ? String(res.data.error) : "no_filedata";
            return { ok: false, error: msg };
        }
        var b64 = String(res.data.filedata).replace(/\s/g, "");
        try {
            var dataUrl = "data:application/octet-stream;base64," + b64;
            var blob = await (await fetch(dataUrl)).blob();
            var blobUrl = URL.createObjectURL(blob);
            var a = document.createElement("a");
            a.href = blobUrl;
            a.target = "_blank";
            a.rel = "noopener noreferrer";
            a.click();
            window.setTimeout(function () {
                URL.revokeObjectURL(blobUrl);
            }, 60000);
            return { ok: true };
        } catch (e) {
            return { ok: false, error: "invalid_base64" };
        }
    }

    /**
     * @param {number} fileId
     * @returns {Promise<{ok: boolean, error?: string}>}
     */
    async function deleteFile(fileId) {
        var res = await window.CheckD.config.apiCall(FILES_DELETE + encodeURIComponent(String(fileId)), { method: "DELETE" });
        if (res.ok && res.data && res.data.ok === true) {
            return { ok: true };
        }
        var err = res.data && res.data.error ? String(res.data.error) : (res.errorCode || "delete_failed");
        return { ok: false, error: err };
    }

    /**
     * @returns {void}
     */
    function clearFilesTable() {
        filesTbody.innerHTML = "";
    }

    /**
     * @param {*} filesPayload
     * @returns {Array<*>}
     */
    function normalizeFilesArray(filesPayload) {
        if (Array.isArray(filesPayload)) {
            return filesPayload;
        }
        if (filesPayload && typeof filesPayload === "object" && (filesPayload.id !== undefined || filesPayload.name !== undefined)) {
            return [filesPayload];
        }
        if (filesPayload && typeof filesPayload === "object") {
            return Object.keys(filesPayload).map(function (k) {
                return filesPayload[k];
            });
        }
        return [];
    }

    /**
     * @returns {Promise<void>}
     */
    async function loadFileList() {
        showListStatus("", true);
        clearFilesTable();
        var res = await window.CheckD.config.apiCall(FILES_LIST, { method: "GET" });
        if (!res.ok || !res.data) {
            var err = res.data && res.data.error ? String(res.data.error) : res.errorCode || "failed_to_load";
            showListStatus("Failed to load files: " + err, false);
            return;
        }
        if (res.data.ok !== true) {
            var err2 = res.data.error ? String(res.data.error) : "failed_to_load";
            showListStatus(err2, false);
            return;
        }
        var rows = normalizeFilesArray(res.data.files);
        if (rows.length === 0) {
            var tr = document.createElement("tr");
            var td = document.createElement("td");
            td.colSpan = 5;
            td.className = "text-muted";
            td.textContent = "No files yet.";
            tr.appendChild(td);
            filesTbody.appendChild(tr);
            return;
        }
        for (var i = 0; i < rows.length; i += 1) {
            var item = rows[i] || {};
            var name = item.name !== undefined && item.name !== null ? String(item.name) : "";
            var fileId = item.id !== undefined && item.id !== null ? Number(item.id) : NaN;
            var idOk = Number.isFinite(fileId) && fileId > 0;
            var tr2 = document.createElement("tr");
            var tdId = document.createElement("td");
            tdId.className = "text-muted font-monospace small";
            tdId.textContent = idOk ? String(fileId) : "—";
            var tdName = document.createElement("td");
            tdName.textContent = name;
            var tdSize = document.createElement("td");
            tdSize.textContent = formatFileSize(item.size);
            var tdCreated = document.createElement("td");
            tdCreated.textContent = item.created_at !== undefined && item.created_at !== null ? String(item.created_at) : "—";
            var tdAct = document.createElement("td");
            tdAct.className = "text-end text-nowrap";
            if (idOk) {
                var btnOpen = document.createElement("button");
                btnOpen.type = "button";
                btnOpen.className = "btn btn-primary btn-sm me-2";
                btnOpen.textContent = "Open";
                btnOpen.dataset.fileId = String(fileId);
                var btnDel = document.createElement("button");
                btnDel.type = "button";
                btnDel.className = "btn btn-danger btn-sm";
                btnDel.textContent = "Delete";
                btnDel.dataset.fileId = String(fileId);
                btnDel.dataset.fileLabel = name;
                btnOpen.dataset.fileLabel = name;
                tdAct.appendChild(btnOpen);
                tdAct.appendChild(btnDel);
            } else {
                tdAct.className = "text-end text-muted small";
                tdAct.textContent = "—";
            }
            tr2.appendChild(tdId);
            tr2.appendChild(tdName);
            tr2.appendChild(tdSize);
            tr2.appendChild(tdCreated);
            tr2.appendChild(tdAct);
            filesTbody.appendChild(tr2);
        }

        var actionBtns = filesTbody.querySelectorAll("button[data-file-id]");
        for (var j = 0; j < actionBtns.length; j += 1) {
            actionBtns[j].addEventListener("click", async function (event) {
                var t = event.currentTarget;
                if (!(t instanceof HTMLButtonElement)) {
                    return;
                }
                var idRaw = t.dataset.fileId;
                var fid = idRaw ? parseInt(idRaw, 10) : NaN;
                if (!Number.isFinite(fid) || fid <= 0) {
                    return;
                }
                var label = t.dataset.fileLabel || "#" + String(fid);
                if (t.classList.contains("btn-danger")) {
                    if (!window.confirm("Delete file \"" + label + "\" (id " + String(fid) + ")?")) {
                        return;
                    }
                    var del = await deleteFile(fid);
                    if (del.ok) {
                        showListStatus("File deleted.", true);
                        await loadFileList();
                    } else {
                        showListStatus("Delete failed: " + (del.error || ""), false);
                    }
                    return;
                }
                var op = await openFileDownload(fid);
                if (!op.ok) {
                    showListStatus("Open failed: " + (op.error || ""), false);
                }
            });
        }
    }

    uploadModalElement.addEventListener("show.bs.modal", function () {
        showUploadModalError("");
        fileUploadInput.value = "";
        uploadFilenameInput.value = "";
    });

    fileUploadInput.addEventListener("change", function () {
        var f = fileUploadInput.files && fileUploadInput.files[0];
        if (f && !uploadFilenameInput.value.trim()) {
            uploadFilenameInput.value = f.name;
        }
    });

    confirmUploadBtn.addEventListener("click", async function () {
        showUploadModalError("");
        var f = fileUploadInput.files && fileUploadInput.files[0];
        if (!f) {
            showUploadModalError("Choose a file first.");
            return;
        }
        var filename = uploadFilenameInput.value.trim() || f.name;
        if (!filename) {
            showUploadModalError("Filename is required.");
            return;
        }
        confirmUploadBtn.disabled = true;
        try {
            var b64 = await fileToBase64(f);
            var res = await window.CheckD.config.apiCall(FILES_NEW, {
                method: "POST",
                body: { filename: filename, filedata: b64 },
            });
            if (res.ok && res.data && res.data.ok === true) {
                uploadModal.hide();
                showListStatus("File uploaded.", true);
                await loadFileList();
                return;
            }
            var err = res.data && res.data.error ? String(res.data.error) : (res.errorCode || "upload_failed");
            showUploadModalError(err);
        } catch (e) {
            showUploadModalError(e && e.message ? String(e.message) : "read_failed");
        } finally {
            confirmUploadBtn.disabled = false;
        }
    });

    navLoginButton.addEventListener("click", function () {
        window.location.href = "login.html";
    });
    logoutButton.addEventListener("click", function () {
        window.CheckD.config.storage.clearAuth();
        window.location.href = "login.html";
    });

    checkSessionButton.addEventListener("click", async function () {
        var result = await checkSession();
        sessionSuccess.textContent = result.ok ? "yes" : "no";
        sessionValid.textContent = result.sessionValid ? "yes" : "no";
        sessionError.textContent = result.error === null ? "null" : result.error;
        sessionModal.show();
    });

    var authToken = window.CheckD.config.storage.get(window.CheckD.config.STORAGE_KEYS.authToken, "");
    var sessionData = parseSessionFromToken(String(authToken || ""));
    if (sessionData && sessionData.username) {
        navUserButton.textContent = sessionData.username;
        navUserGroup.hidden = false;
        navLoginButton.hidden = true;
    } else {
        navUserGroup.hidden = true;
        navLoginButton.hidden = false;
    }

    loadFileList();
})();
