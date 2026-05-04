(function () {
    /**
     * @typedef {Object} SessionPayload
     * @property {string=} username
     * @property {number=} userID
     * @property {number=} userRole
     * @property {string=} expires
     */

    /**
     * @typedef {Object} ChecklistQuestion
     * @property {string} q_name
     * @property {string} title
     * @property {string} description
     * @property {string} q_type
     * @property {string[]=} q_values
     */

    /**
     * @typedef {Object} ChecklistDraft
     * @property {number=} id
     * @property {number=} owner
     * @property {string} name
     * @property {string} description
     * @property {boolean} is_public
     * @property {boolean} is_hidden
     * @property {ChecklistQuestion[]} questions
     */

    /** @type {ChecklistDraft} */
    let draft = {
        name: "",
        description: "",
        is_public: true,
        is_hidden: false,
        questions: [],
    };

    /** @type {HTMLElement | null} */
    const navUserGroup = document.getElementById("nav-user-group");
    /** @type {HTMLButtonElement | null} */
    const navUserButton = document.getElementById("nav-user-button");
    /** @type {HTMLButtonElement | null} */
    const navLoginButton = document.getElementById("nav-login-button");
    /** @type {HTMLButtonElement | null} */
    const checkSessionButton = document.getElementById("check-session-btn");
    /** @type {HTMLButtonElement | null} */
    const logoutButton = document.getElementById("logout-btn");

    const checklistTitle = document.getElementById("checklist-title");
    const checklistDescriptionText = document.getElementById("checklist-description-text");
    const checklistPublicBadge = document.getElementById("checklist-public-badge");
    const checklistHiddenBadge = document.getElementById("checklist-hidden-badge");

    /** @type {HTMLElement | null} */
    const questionsContainer = document.getElementById("questions-container");
    /** @type {HTMLButtonElement | null} */
    const saveChecklistButton = document.getElementById("save-checklist-btn");
    /** @type {HTMLButtonElement | null} */
    const discardChecklistButton = document.getElementById("discard-checklist-btn");
    /** @type {HTMLButtonElement | null} */
    const addQuestionOpenButton = document.getElementById("add-question-open-btn");
    /** @type {HTMLElement | null} */
    const saveResult = document.getElementById("save-result");

    /** @type {HTMLElement | null} */
    const questionModalElement = document.getElementById("questionModal");
    /** @type {HTMLInputElement | null} */
    const qTitleInput = document.getElementById("q-title");
    /** @type {HTMLTextAreaElement | null} */
    const qDescInput = document.getElementById("q-desc");
    /** @type {HTMLSelectElement | null} */
    const qTypeInput = document.getElementById("q-type");
    /** @type {HTMLElement | null} */
    const questionValuesSection = document.getElementById("question-values-section");
    /** @type {HTMLElement | null} */
    const questionValuesContainer = document.getElementById("question-values-container");
    /** @type {HTMLButtonElement | null} */
    const addAnswerButton = document.getElementById("add-answer-btn");
    /** @type {HTMLButtonElement | null} */
    const createQuestionButton = document.getElementById("create-question-btn");
    const questionModalTitle = document.getElementById("question-modal-title");

    /** @type {HTMLElement | null} */
    const sessionModalElement = document.getElementById("sessionCheckModal");
    const sessionSuccess = document.getElementById("session-check-success");
    const sessionValid = document.getElementById("session-check-valid");
    const sessionError = document.getElementById("session-check-error");

    if (
        !navUserGroup || !navUserButton || !navLoginButton || !checkSessionButton || !logoutButton ||
        !checklistTitle || !checklistDescriptionText || !checklistPublicBadge || !checklistHiddenBadge ||
        !questionsContainer || !saveChecklistButton || !discardChecklistButton || !addQuestionOpenButton || !saveResult ||
        !questionModalElement || !qTitleInput || !qDescInput || !qTypeInput || !questionValuesSection || !questionValuesContainer ||
        !addAnswerButton || !createQuestionButton || !questionModalTitle || !sessionModalElement
    ) {
        return;
    }

    const questionModal = new bootstrap.Modal(questionModalElement);
    const sessionModal = new bootstrap.Modal(sessionModalElement);
    /** @type {number | null} */
    let editingQuestionIndex = null;

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
     * @param {string} text
     * @param {boolean} isSuccess
     * @returns {void}
     */
    function showSaveResult(text, isSuccess) {
        saveResult.innerHTML = "";
        const alert = document.createElement("div");
        alert.className = "alert " + (isSuccess ? "alert-success" : "alert-danger");
        alert.textContent = text;
        saveResult.appendChild(alert);
    }

    /**
     * @returns {{mode: string, id: string}}
     */
    function getModeState() {
        const params = new URLSearchParams(window.location.search);
        return {
            mode: params.get("mode") || "new",
            id: params.get("id") || "",
        };
    }

    /**
     * @param {*} responseData
     * @returns {number | null}
     */
    function extractChecklistId(responseData) {
        if (!responseData) {
            return null;
        }
        if (typeof responseData.id === "number") {
            return responseData.id;
        }
        if (responseData.checklist && typeof responseData.checklist.id === "number") {
            return responseData.checklist.id;
        }
        if (typeof responseData.checklist_id === "number") {
            return responseData.checklist_id;
        }
        return null;
    }

    /**
     * @param {number} checklistId
     * @returns {void}
     */
    function switchToEditMode(checklistId) {
        draft.id = checklistId;
        const nextUrl = new URL(window.location.href);
        nextUrl.searchParams.set("mode", "edit");
        nextUrl.searchParams.set("id", String(checklistId));
        window.history.replaceState({}, "", nextUrl.toString());
    }

    /**
     * @returns {void}
     */
    function renderChecklistMeta() {
        checklistTitle.textContent = draft.name || "Checklist editor";
        checklistDescriptionText.textContent = draft.description || "No description.";

        checklistPublicBadge.textContent = draft.is_public ? "Public" : "Private";
        checklistPublicBadge.className = draft.is_public ? "badge text-bg-primary me-2" : "badge text-bg-dark me-2";

        checklistHiddenBadge.textContent = draft.is_hidden ? "Hidden" : "Visible";
        checklistHiddenBadge.className = draft.is_hidden ? "badge text-bg-secondary" : "badge text-bg-success";
    }

    /**
     * @param {*} rawQuestion
     * @param {number} index
     * @returns {ChecklistQuestion}
     */
    function normalizeQuestion(rawQuestion, index) {
        const qType = rawQuestion && rawQuestion.q_type ? String(rawQuestion.q_type) : "text";
        const normalized = {
            q_name: rawQuestion && rawQuestion.q_name ? String(rawQuestion.q_name) : "Question #" + (index + 1),
            title: rawQuestion && rawQuestion.title ? String(rawQuestion.title) : "",
            description: rawQuestion && rawQuestion.description ? String(rawQuestion.description) : "",
            q_type: qType,
        };

        if ((qType === "single" || qType === "multi") && rawQuestion && Array.isArray(rawQuestion.q_values)) {
            normalized.q_values = rawQuestion.q_values.map(function (value) {
                return String(value);
            });
        }
        return normalized;
    }

    /**
     * @returns {ChecklistDraft | null}
     */
    function loadDraftFromBootstrap() {
        const seed = window.CheckD.config.storage.get(window.CheckD.config.STORAGE_KEYS.editorBootstrap, null);
        if (!seed) {
            return null;
        }
        return {
            name: seed.name ? String(seed.name) : "",
            description: seed.description ? String(seed.description) : "",
            is_public: seed.is_public === true,
            is_hidden: seed.is_hidden === true,
            questions: [],
        };
    }

    /**
     * @param {string} checklistId
     * @returns {Promise<ChecklistDraft | null>}
     */
    async function loadDraftFromApi(checklistId) {
        const result = await window.CheckD.config.apiCall("/checklists/get?id=" + encodeURIComponent(checklistId), {
            method: "GET",
        });

        if (!result.ok || !result.data) {
            return null;
        }

        const data = result.data.checklist ? result.data.checklist : result.data;
        if (!data || typeof data !== "object") {
            return null;
        }

        /** @type {ChecklistDraft} */
        const loaded = {
            id: data.id,
            owner: data.owner && data.owner.id !== undefined ? data.owner.id : data.owner,
            name: data.name ? String(data.name) : "",
            description: data.description ? String(data.description) : "",
            is_public: data.is_public === true,
            is_hidden: data.is_hidden === true,
            questions: [],
        };

        if (Array.isArray(data.questions)) {
            for (let i = 0; i < data.questions.length; i += 1) {
                loaded.questions.push(normalizeQuestion(data.questions[i], i));
            }
        }

        return loaded;
    }

    /**
     * @returns {void}
     */
    function resetQuestionModal() {
        qTitleInput.value = "";
        qDescInput.value = "";
        qTypeInput.value = "bool";
        questionValuesContainer.innerHTML = "";
        addAnswerInput();
        addAnswerInput();
        toggleAnswerEditor();
        questionModalTitle.textContent = "Create new question";
        createQuestionButton.textContent = "Create";
        editingQuestionIndex = null;
    }

    /**
     * @returns {void}
     */
    function toggleAnswerEditor() {
        const type = qTypeInput.value;
        questionValuesSection.hidden = type === "bool" || type === "text";
    }

    /**
     * @returns {void}
     */
    function addAnswerInput() {
        const row = document.createElement("div");
        row.className = "input-group mb-2";
        row.innerHTML = "" +
            "<input type=\"text\" class=\"form-control question-answer-input\" placeholder=\"Answer value\">" +
            "<button class=\"btn btn-outline-danger remove-answer-btn\" type=\"button\">Delete</button>";
        questionValuesContainer.appendChild(row);

        const removeButton = row.querySelector(".remove-answer-btn");
        if (removeButton) {
            removeButton.addEventListener("click", function () {
                row.remove();
            });
        }
    }

    /**
     * @param {ChecklistQuestion} question
     * @returns {void}
     */
    function openQuestionEditor(question) {
        qTitleInput.value = question.title;
        qDescInput.value = question.description;
        qTypeInput.value = question.q_type;
        questionValuesContainer.innerHTML = "";

        if (question.q_type === "single" || question.q_type === "multi") {
            const values = question.q_values || [];
            if (values.length === 0) {
                addAnswerInput();
            } else {
                for (let i = 0; i < values.length; i += 1) {
                    addAnswerInput();
                    const inputs = questionValuesContainer.querySelectorAll(".question-answer-input");
                    const input = inputs[inputs.length - 1];
                    if (input instanceof HTMLInputElement) {
                        input.value = values[i];
                    }
                }
            }
        } else {
            addAnswerInput();
            addAnswerInput();
        }

        toggleAnswerEditor();
        questionModalTitle.textContent = "Edit question";
        createQuestionButton.textContent = "Save";
        questionModal.show();
    }

    /**
     * @returns {string[]}
     */
    function collectQuestionValues() {
        const values = [];
        const inputs = questionValuesContainer.querySelectorAll(".question-answer-input");
        for (let i = 0; i < inputs.length; i += 1) {
            const input = inputs[i];
            if (!(input instanceof HTMLInputElement)) {
                continue;
            }
            const value = input.value.trim();
            if (value) {
                values.push(value);
            }
        }
        return values;
    }

    /**
     * @returns {void}
     */
    function renderQuestions() {
        questionsContainer.innerHTML = "";
        if (draft.questions.length === 0) {
            const row = document.createElement("tr");
            row.innerHTML = "<td><p class=\"text-secondary mb-0\">No questions yet.</p></td>";
            questionsContainer.appendChild(row);
            return;
        }

        for (let i = 0; i < draft.questions.length; i += 1) {
            const question = draft.questions[i];
            const row = document.createElement("tr");
            const valuesText = question.q_values && question.q_values.length > 0
                ? question.q_values.join(", ")
                : "n/a";
            row.innerHTML = "" +
                "<td>" +
                "<h5 class=\"mb-2\">" + question.q_name + ": " + question.title + "</h5>" +
                "<p class=\"mb-2\"><strong>Type:</strong> " + question.q_type + "</p>" +
                "<p class=\"mb-2\"><strong>Description:</strong> " + question.description + "</p>" +
                "<p class=\"mb-0\"><strong>Values:</strong> " + valuesText + "</p>" +
                "</td>" +
                "<td class=\"text-end align-top\">" +
                "<div class=\"d-inline-flex flex-column gap-2\">" +
                "<button type=\"button\" class=\"btn btn-sm btn-outline-danger delete-question-btn\" data-index=\"" + i + "\">Delete</button>" +
                "<button type=\"button\" class=\"btn btn-sm btn-outline-primary edit-question-btn\" data-index=\"" + i + "\">Edit</button>" +
                "</div>" +
                "</td>";
            questionsContainer.appendChild(row);
        }

        const deleteButtons = questionsContainer.querySelectorAll(".delete-question-btn");
        for (let i = 0; i < deleteButtons.length; i += 1) {
            deleteButtons[i].addEventListener("click", function (event) {
                const target = event.currentTarget;
                if (!(target instanceof HTMLButtonElement)) {
                    return;
                }
                const index = Number(target.dataset.index);
                if (Number.isNaN(index)) {
                    return;
                }
                draft.questions.splice(index, 1);
                renderQuestions();
            });
        }

        const editButtons = questionsContainer.querySelectorAll(".edit-question-btn");
        for (let i = 0; i < editButtons.length; i += 1) {
            editButtons[i].addEventListener("click", function (event) {
                const target = event.currentTarget;
                if (!(target instanceof HTMLButtonElement)) {
                    return;
                }
                const index = Number(target.dataset.index);
                if (Number.isNaN(index) || !draft.questions[index]) {
                    return;
                }
                editingQuestionIndex = index;
                openQuestionEditor(draft.questions[index]);
            });
        }
    }

    /**
     * @returns {ChecklistDraft}
     */
    function buildPayload() {
        return {
            id: draft.id,
            owner: draft.owner,
            name: draft.name,
            description: draft.description,
            is_public: draft.is_public,
            is_hidden: draft.is_hidden,
            questions: draft.questions,
        };
    }

    /**
     * @returns {void}
     */
    function clearDraft() {
        draft.questions = [];
        saveResult.innerHTML = "";
        renderQuestions();
    }

    /**
     * @returns {Promise<void>}
     */
    async function initializeDraft() {
        const state = getModeState();
        if (state.mode === "edit") {
            if (!state.id) {
                showSaveResult("Missing checklist id for edit mode.", false);
                return;
            }
            const loaded = await loadDraftFromApi(state.id);
            if (!loaded) {
                showSaveResult("Failed to load checklist for edit mode.", false);
                return;
            }
            draft = loaded;
            renderChecklistMeta();
            renderQuestions();
            return;
        }

        const seeded = loadDraftFromBootstrap();
        if (!seeded) {
            showSaveResult("Create checklist from editor modal first.", false);
            return;
        }
        draft = seeded;
        window.CheckD.config.storage.remove(window.CheckD.config.STORAGE_KEYS.editorBootstrap);
        renderChecklistMeta();
        draft.questions = [];
        renderQuestions();
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

    qTypeInput.addEventListener("change", toggleAnswerEditor);
    addAnswerButton.addEventListener("click", addAnswerInput);
    addQuestionOpenButton.addEventListener("click", function () {
        resetQuestionModal();
        questionModal.show();
    });

    createQuestionButton.addEventListener("click", function () {
        const title = qTitleInput.value.trim();
        const description = qDescInput.value.trim();
        const qType = qTypeInput.value;

        if (!title) {
            showSaveResult("Question title is required.", false);
            return;
        }

        /** @type {ChecklistQuestion} */
        const question = {
            q_name: editingQuestionIndex === null
                ? "Question #" + (draft.questions.length + 1)
                : draft.questions[editingQuestionIndex].q_name,
            title: title,
            description: description,
            q_type: qType,
        };

        if (qType === "single" || qType === "multi") {
            const values = collectQuestionValues();
            if (values.length === 0) {
                showSaveResult("Add at least one answer value for single/multi question.", false);
                return;
            }
            question.q_values = values;
        }

        if (editingQuestionIndex === null) {
            draft.questions.push(question);
            showSaveResult("Question added.", true);
        } else {
            draft.questions[editingQuestionIndex] = question;
            showSaveResult("Question updated.", true);
        }

        renderQuestions();
        resetQuestionModal();
        questionModal.hide();
    });

    saveChecklistButton.addEventListener("click", async function () {
        const payload = buildPayload();
        if (payload.questions.length === 0) {
            showSaveResult("Add at least one question before saving.", false);
            return;
        }

        const state = getModeState();
        const endpoint = "/user/checklists";
        const method = state.mode === "edit" ? "PUT" : "POST";

        const result = await window.CheckD.config.apiCall(endpoint, {
            method: method,
            body: payload,
        });

        if (!result.ok || !result.data || result.data.ok !== true) {
            const errorText = result.data && result.data.error ? String(result.data.error) : result.errorCode || "save_failed";
            showSaveResult("Save failed: " + errorText, false);
            return;
        }

        if (state.mode !== "edit") {
            const createdId = extractChecklistId(result.data);
            if (createdId !== null) {
                switchToEditMode(createdId);
            }
        }

        showSaveResult("Checklist saved successfully.", true);
    });

    discardChecklistButton.addEventListener("click", function () {
        clearDraft();
        window.CheckD.config.storage.remove(window.CheckD.config.STORAGE_KEYS.editorBootstrap);
        window.location.href = "edit.html";
    });

    questionModalElement.addEventListener("shown.bs.modal", function () {
        qTitleInput.focus();
    });

    initializeDraft();
})();
