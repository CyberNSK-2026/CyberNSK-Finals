(function () {
    /**
     * @typedef {Object} ChecklistQuestion
     * @property {number} id
     * @property {string} q_name
     * @property {string} title
     * @property {string} description
     * @property {string} q_type
     * @property {string[]=} q_values
     */

    /**
     * @typedef {Object} ChecklistData
     * @property {number} id
     * @property {string} name
     * @property {string} description
     * @property {ChecklistQuestion[]} questions
     */

    /** @type {ChecklistData | null} */
    let checklist = null;

    const checklistTitle = document.getElementById("checklist-title");
    const checklistDescription = document.getElementById("checklist-description");
    const questionsContainer = document.getElementById("questions-container");
    const submitButton = document.getElementById("submit-checklist-btn");
    const resultBox = document.getElementById("complete-result");
    const navLoginButton = document.getElementById("nav-login-button");
    const navUserGroup = document.getElementById("nav-user-group");
    const navUserButton = document.getElementById("nav-user-button");
    const checkSessionButton = document.getElementById("check-session-btn");
    const logoutButton = document.getElementById("logout-btn");
    const sessionModalElement = document.getElementById("sessionCheckModal");

    if (
        !checklistTitle || !checklistDescription || !questionsContainer || !submitButton || !resultBox || !navLoginButton ||
        !navUserGroup || !navUserButton || !checkSessionButton || !logoutButton || !sessionModalElement
    ) {
        return;
    }

    const sessionModal = new bootstrap.Modal(sessionModalElement);
    const sessionSuccess = document.getElementById("session-check-success");
    const sessionValid = document.getElementById("session-check-valid");
    const sessionError = document.getElementById("session-check-error");

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
     * @returns {{username?: string} | null}
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

    navLoginButton.addEventListener("click", function () {
        window.location.href = "login.html";
    });
    logoutButton.addEventListener("click", function () {
        window.CheckD.config.storage.clearAuth();
        window.location.href = "login.html";
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

    /**
     * @param {string} message
     * @param {boolean} isSuccess
     * @returns {void}
     */
    function showResult(message, isSuccess) {
        resultBox.innerHTML = "";
        if (!message) {
            return;
        }
        const alert = document.createElement("div");
        alert.className = "alert " + (isSuccess ? "alert-success" : "alert-danger");
        alert.textContent = message;
        resultBox.appendChild(alert);
    }

    /**
     * @param {*} raw
     * @param {number} index
     * @returns {ChecklistQuestion}
     */
    function normalizeQuestion(raw, index) {
        const qType = raw && raw.q_type ? String(raw.q_type) : "text";
        /** @type {ChecklistQuestion} */
        const normalized = {
            id: raw && typeof raw.id === "number" ? raw.id : index + 1,
            q_name: raw && raw.q_name ? String(raw.q_name) : "Question #" + (index + 1),
            title: raw && raw.title ? String(raw.title) : "",
            description: raw && raw.description ? String(raw.description) : "",
            q_type: qType,
        };
        if (Array.isArray(raw && raw.q_values)) {
            normalized.q_values = raw.q_values.map(function (value) {
                return String(value);
            });
        }
        return normalized;
    }

    /**
     * @param {*} rawData
     * @returns {ChecklistData | null}
     */
    function normalizeChecklist(rawData) {
        const data = rawData && rawData.checklist ? rawData.checklist : rawData;
        if (!data || typeof data !== "object" || typeof data.id !== "number") {
            return null;
        }

        /** @type {ChecklistData} */
        const normalized = {
            id: data.id,
            name: data.name ? String(data.name) : "Checklist #" + String(data.id),
            description: data.description ? String(data.description) : "",
            questions: [],
        };

        if (Array.isArray(data.questions)) {
            for (let i = 0; i < data.questions.length; i += 1) {
                normalized.questions.push(normalizeQuestion(data.questions[i], i));
            }
        }
        return normalized;
    }

    /**
     * @param {ChecklistQuestion} question
     * @param {number} index
     * @returns {HTMLElement}
     */
    function renderQuestion(question, index) {
        const tr = document.createElement("tr");
        tr.className = "question-row";
        tr.dataset.questionId = String(question.id);
        const td = document.createElement("td");
        const wrapper = document.createElement("div");

        const title = document.createElement("h5");
        title.textContent = question.q_name || ("Question #" + String(index + 1));
        wrapper.appendChild(title);

        const description = document.createElement("p");
        description.textContent = question.description || question.title || "";
        wrapper.appendChild(description);

        const answerKey = "question-" + String(question.id);

        if (question.q_type === "bool") {
            const group = document.createElement("div");
            group.className = "btn-group";
            group.innerHTML = "" +
                "<input type=\"radio\" class=\"btn-check\" name=\"" + answerKey + "\" id=\"" + answerKey + "-yes\" value=\"yes\" autocomplete=\"off\">" +
                "<label class=\"btn btn-outline-primary\" for=\"" + answerKey + "-yes\">Yes</label>" +
                "<input type=\"radio\" class=\"btn-check\" name=\"" + answerKey + "\" id=\"" + answerKey + "-no\" value=\"no\" autocomplete=\"off\">" +
                "<label class=\"btn btn-outline-primary\" for=\"" + answerKey + "-no\">No</label>";
            wrapper.appendChild(group);
        } else if (question.q_type === "single") {
            const values = question.q_values || [];
            const row = document.createElement("div");
            row.className = "row g-2";
            for (let i = 0; i < values.length; i += 1) {
                const col = document.createElement("div");
                col.className = "col-12";
                const optionId = answerKey + "-single-" + String(i);
                col.innerHTML = "" +
                    "<input type=\"radio\" class=\"btn-check\" name=\"" + answerKey + "\" id=\"" + optionId + "\" value=\"" + values[i] + "\" autocomplete=\"off\">" +
                    "<label class=\"btn btn-outline-secondary w-100 text-start\" for=\"" + optionId + "\">" + values[i] + "</label>";
                row.appendChild(col);
            }
            wrapper.appendChild(row);
        } else if (question.q_type === "multi") {
            const values = question.q_values || [];
            const row = document.createElement("div");
            row.className = "row g-2";
            for (let i = 0; i < values.length; i += 1) {
                const col = document.createElement("div");
                col.className = "col-12";
                const optionId = answerKey + "-multi-" + String(i);
                col.innerHTML = "" +
                    "<input type=\"checkbox\" class=\"btn-check\" name=\"" + answerKey + "\" id=\"" + optionId + "\" value=\"" + values[i] + "\" autocomplete=\"off\">" +
                    "<label class=\"btn btn-outline-secondary w-100 text-start\" for=\"" + optionId + "\">" + values[i] + "</label>";
                row.appendChild(col);
            }
            wrapper.appendChild(row);
        } else {
            const textArea = document.createElement("textarea");
            textArea.className = "form-control";
            textArea.rows = 4;
            textArea.id = answerKey + "-text";
            textArea.dataset.questionId = String(question.id);
            wrapper.appendChild(textArea);
        }

        td.appendChild(wrapper);
        tr.appendChild(td);

        const inputs = tr.querySelectorAll("input, textarea");
        for (let i = 0; i < inputs.length; i += 1) {
            inputs[i].addEventListener("change", function () {
                tr.classList.remove("is-invalid-question");
            });
            inputs[i].addEventListener("input", function () {
                tr.classList.remove("is-invalid-question");
            });
        }

        return tr;
    }

    /**
     * @returns {void}
     */
    function renderChecklist() {
        if (!checklist) {
            return;
        }
        checklistTitle.textContent = checklist.name;
        checklistDescription.textContent = checklist.description || "Complete all questions and submit your answers.";
        questionsContainer.innerHTML = "";

        for (let i = 0; i < checklist.questions.length; i += 1) {
            questionsContainer.appendChild(renderQuestion(checklist.questions[i], i));
        }
    }

    /**
     * @returns {Array<{question_id: number, answers: string[]}>}
     */
    function collectAnswers() {
        if (!checklist) {
            return [];
        }

        /** @type {Array<{question_id: number, answers: string[]}>} */
        const answerRows = [];
        for (let i = 0; i < checklist.questions.length; i += 1) {
            const q = checklist.questions[i];
            const answerKey = "question-" + String(q.id);
            /** @type {string[]} */
            let answers = [];

            if (q.q_type === "bool" || q.q_type === "single") {
                const selected = document.querySelector("input[name=\"" + answerKey + "\"]:checked");
                if (selected instanceof HTMLInputElement) {
                    answers = [selected.value];
                }
            } else if (q.q_type === "multi") {
                const selected = document.querySelectorAll("input[name=\"" + answerKey + "\"]:checked");
                answers = [];
                for (let j = 0; j < selected.length; j += 1) {
                    const input = selected[j];
                    if (input instanceof HTMLInputElement) {
                        answers.push(input.value);
                    }
                }
            } else {
                const textArea = document.getElementById(answerKey + "-text");
                if (textArea instanceof HTMLTextAreaElement) {
                    const value = textArea.value.trim();
                    answers = value ? [value] : [];
                }
            }

            answerRows.push({
                question_id: q.id,
                answers: answers,
            });
        }
        return answerRows;
    }

    /**
     * @returns {{ok: boolean, error: string}}
     */
    function validateAllAnswers() {
        if (!checklist) {
            return {
                ok: false,
                error: "Checklist is not loaded.",
            };
        }

        const rows = questionsContainer.querySelectorAll("tr.question-row");
        for (let r = 0; r < rows.length; r += 1) {
            rows[r].classList.remove("is-invalid-question");
        }

        /** @type {string[]} */
        const missingLabels = [];

        for (let i = 0; i < checklist.questions.length; i += 1) {
            const q = checklist.questions[i];
            const answerKey = "question-" + String(q.id);
            let hasAnswer = false;

            if (q.q_type === "bool" || q.q_type === "single") {
                const selected = document.querySelector("input[name=\"" + answerKey + "\"]:checked");
                hasAnswer = selected instanceof HTMLInputElement;
            } else if (q.q_type === "multi") {
                const selected = document.querySelectorAll("input[name=\"" + answerKey + "\"]:checked");
                hasAnswer = selected.length > 0;
            } else {
                const textArea = document.getElementById(answerKey + "-text");
                if (textArea instanceof HTMLTextAreaElement) {
                    hasAnswer = textArea.value.trim().length > 0;
                }
            }

            if (!hasAnswer) {
                const row = questionsContainer.querySelector("tr.question-row[data-question-id=\"" + String(q.id) + "\"]");
                if (row) {
                    row.classList.add("is-invalid-question");
                }
                missingLabels.push(q.q_name || ("Question #" + String(i + 1)));
            }
        }

        if (missingLabels.length > 0) {
            return {
                ok: false,
                error: "Please answer all questions. Missing: " + missingLabels.join(", "),
            };
        }

        return {
            ok: true,
            error: "",
        };
    }

    /**
     * @returns {Promise<void>}
     */
    async function loadChecklist() {
        const params = new URLSearchParams(window.location.search);
        const id = params.get("id");
        if (!id) {
            showResult("Checklist id is required in query string.", false);
            return;
        }

        const result = await window.CheckD.config.apiCall("/checklists/get?id=" + encodeURIComponent(id), {
            method: "GET",
        });
        if (!result.ok || !result.data) {
            const errorText = result.data && result.data.error ? String(result.data.error) : result.errorCode || "failed_to_load";
            showResult("Failed to load checklist: " + errorText, false);
            return;
        }

        const loaded = normalizeChecklist(result.data);
        if (!loaded) {
            showResult("Checklist response has unsupported format.", false);
            return;
        }

        checklist = loaded;
        showResult("", true);
        renderChecklist();
    }

    submitButton.addEventListener("click", async function () {
        if (!checklist) {
            showResult("Checklist is not loaded.", false);
            return;
        }

        const validation = validateAllAnswers();
        if (!validation.ok) {
            showResult(validation.error, false);
            return;
        }

        const payload = {
            checklist_id: checklist.id,
            answers: collectAnswers(),
        };

        submitButton.disabled = true;
        const result = await window.CheckD.config.apiCall("/checklists/complete", {
            method: "POST",
            body: payload,
        });

        if (!result.ok || !result.data || result.data.ok !== true) {
            submitButton.disabled = false;
            const errorText = result.data && result.data.error ? String(result.data.error) : result.errorCode || "submit_failed";
            showResult("Submit failed: " + errorText, false);
            return;
        }

        const rows = questionsContainer.querySelectorAll("tr.question-row");
        for (let r = 0; r < rows.length; r += 1) {
            rows[r].classList.remove("is-invalid-question");
        }

        showResult("Checklist submitted successfully.", true);
        window.setTimeout(function () {
            window.location.replace("index.html");
        }, 1000);
    });

    loadChecklist();
})();
