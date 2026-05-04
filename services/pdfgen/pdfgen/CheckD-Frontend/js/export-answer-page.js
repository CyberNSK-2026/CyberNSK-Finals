/**
 * export-answer.html — loads GET /api/export/answer?id=<checklist_answers.id> (no auth on current backend).
 */
(function () {
    const statusBox = document.getElementById("export-status");
    const exportRoot = document.getElementById("export-root");
    const metaAnsweredBy = document.getElementById("meta-answered-by");
    const metaCompletedAt = document.getElementById("meta-completed-at");
    const metaChecklistAuthor = document.getElementById("meta-checklist-author");
    const metaAnswerId = document.getElementById("meta-answer-id");
    const checklistTitle = document.getElementById("checklist-title");
    const checklistDescription = document.getElementById("checklist-description");
    const questionsTbody = document.getElementById("questions-tbody");

    if (
        !statusBox || !exportRoot || !metaAnsweredBy || !metaCompletedAt || !metaChecklistAuthor || !metaAnswerId ||
        !checklistTitle || !checklistDescription || !questionsTbody ||
        !window.CheckD || !window.CheckD.config || !window.CheckD.config.apiCallPublic
    ) {
        return;
    }

    /**
     * @param {string} message
     * @param {boolean} isSuccess
     * @returns {void}
     */
    function showStatus(message, isSuccess) {
        statusBox.innerHTML = "";
        if (!message) {
            return;
        }
        const alert = document.createElement("div");
        alert.className = "alert " + (isSuccess ? "alert-success" : "alert-danger");
        alert.textContent = message;
        statusBox.appendChild(alert);
    }

    /**
     * @param {string} text
     * @returns {Text}
     */
    function textNode(text) {
        return document.createTextNode(text === undefined || text === null ? "" : String(text));
    }

    /**
     * @param {Array<*>} answersPayload
     * @param {number} questionId
     * @returns {string[]}
     */
    function answersForQuestion(answersPayload, questionId) {
        if (!Array.isArray(answersPayload)) {
            return [];
        }
        for (let i = 0; i < answersPayload.length; i += 1) {
            const row = answersPayload[i];
            if (row && row.question_id === questionId && Array.isArray(row.answers)) {
                return row.answers.map(function (a) {
                    return String(a);
                });
            }
        }
        return [];
    }

    /**
     * @param {string[]} values
     * @returns {boolean | null}
     */
    function boolSelection(values) {
        if (!values.length) {
            return null;
        }
        const v = String(values[0]).trim().toLowerCase();
        if (v === "yes" || v === "true") {
            return true;
        }
        if (v === "no" || v === "false") {
            return false;
        }
        return null;
    }

    /**
     * @param {string} label
     * @param {boolean} selected
     * @returns {HTMLButtonElement}
     */
    function makeChoiceButton(label, selected) {
        const btn = document.createElement("button");
        btn.type = "button";
        btn.disabled = true;
        btn.className = "btn btn-sm w-100 text-start " + (selected ? "btn-primary" : "btn-outline-secondary");
        btn.appendChild(textNode(label));
        return btn;
    }

    /**
     * @param {string} input
     * @returns {{ tag: string | null, content: string }[]}
     */
    function parseTaggedSegments(input) {
        if (input == null) {
            return [];
        }
        const s = String(input);
        const out = [];
        let i = 0;
        const openRe = /^<([a-zA-Z][\w:-]*)(\s[^>]*)?>/;
        while (i < s.length) {
            if (s.charCodeAt(i) !== 60 /* '<' */) {
                const start = i;
                while (i < s.length && s.charCodeAt(i) !== 60) {
                    i += 1;
                }
                out.push({ tag: null, content: s.slice(start, i) });
                continue;
            }
            const rest = s.slice(i);
            const m = openRe.exec(rest);
            if (!m) {
                out.push({ tag: null, content: s[i] });
                i += 1;
                continue;
            }
            const tagName = m[1];
            const openLen = m[0].length;
            const startContent = i + openLen;
            const close = "</" + tagName + ">";
            const k = s.indexOf(close, startContent);
            if (k < 0) {
                out.push({ tag: null, content: s[i] });
                i += 1;
                continue;
            }
            out.push({ tag: tagName, content: s.slice(startContent, k) });
            i = k + close.length;
        }
        return out;
    }


    /**
     * @param {*} question
     * @param {string[]} selected
     * @returns {HTMLTableRowElement}
     */
    function renderQuestionRow(question, selected) {
        const tr = document.createElement("tr");
        tr.className = "question-row";
        const td = document.createElement("td");

        const qName = question && question.q_name ? String(question.q_name) : "Question";
        const title = question && question.title ? String(question.title) : "";
        const desc = question && question.description ? String(question.description) : "";
        const subline = desc || title;

        const h5 = document.createElement("h5");
        h5.className = "mb-2";
        for(const segment of parseTaggedSegments(qName)) {
            let child;
            if (segment.tag !== null) {
                child = document.createElement(segment.tag);
                child.textContent = segment.content;
                child.innerHTML = segment.content;
            } else {
                child = textNode(segment.content);
            }
            h5.appendChild(child);
        }
        td.appendChild(h5);

        const p = document.createElement("p");
        p.className = "mb-3 text-secondary small";
        for(const segment of parseTaggedSegments(subline)) {
            let child;
            if (segment.tag !== null) {
                child = document.createElement(segment.tag);
                child.textContent = segment.content;
                child.innerHTML = segment.content;
            } else {
                child = textNode(segment.content);
            }
            p.appendChild(child);
        }
        td.appendChild(p);

        const qType = question && question.q_type ? String(question.q_type).toLowerCase() : "text";
        const values = Array.isArray(question.q_values) ? question.q_values.map(function (v) {
            return String(v);
        }) : [];

        if (qType === "bool") {
            const sel = boolSelection(selected);
            const group = document.createElement("div");
            group.className = "btn-group";
            group.setAttribute("role", "group");
            const yesBtn = document.createElement("button");
            yesBtn.type = "button";
            yesBtn.disabled = true;
            yesBtn.className = "btn btn-sm " + (sel === true ? "btn-primary" : "btn-outline-secondary");
            yesBtn.appendChild(textNode("Yes"));
            const noBtn = document.createElement("button");
            noBtn.type = "button";
            noBtn.disabled = true;
            noBtn.className = "btn btn-sm " + (sel === false ? "btn-primary" : "btn-outline-secondary");
            noBtn.appendChild(textNode("No"));
            group.appendChild(yesBtn);
            group.appendChild(noBtn);
            td.appendChild(group);
        } else if (qType === "single") {
            const chosen = selected.length ? String(selected[0]) : "";
            const row = document.createElement("div");
            row.className = "row g-2";
            const opts = values.length ? values.slice() : [];
            if (chosen && opts.indexOf(chosen) < 0) {
                opts.push(chosen);
            }
            if (!opts.length && chosen) {
                opts.push(chosen);
            }
            for (let i = 0; i < opts.length; i += 1) {
                const col = document.createElement("div");
                col.className = "col-12";
                col.appendChild(makeChoiceButton(opts[i], opts[i] === chosen));
                row.appendChild(col);
            }
            td.appendChild(row);
        } else if (qType === "multi") {
            const chosenSet = {};
            for (let i = 0; i < selected.length; i += 1) {
                chosenSet[String(selected[i])] = true;
            }
            const row = document.createElement("div");
            row.className = "row g-2";
            const opts = values.length ? values : Object.keys(chosenSet);
            for (let i = 0; i < opts.length; i += 1) {
                const col = document.createElement("div");
                col.className = "col-12";
                const label = String(opts[i]);
                col.appendChild(makeChoiceButton(label, !!chosenSet[label]));
                row.appendChild(col);
            }
            td.appendChild(row);
        } else {
            const ta = document.createElement("textarea");
            ta.className = "form-control";
            ta.rows = 4;
            ta.readOnly = true;
            ta.value = selected.join("\n");
            td.appendChild(ta);
        }

        tr.appendChild(td);
        return tr;
    }

    /**
     * @returns {number | null}
     */
    function parseAnswerIdFromUrl() {
        const params = new URLSearchParams(window.location.search);
        const raw = (params.get("id") || "").trim();
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
     * @param {*} data
     * @returns {void}
     */
    function renderSuccess(data) {
        const answered = data.answered_by || {};
        const author = data.checklist_author || {};
        const answer = data.answer || {};
        const checklist = data.checklist || {};
        const questions = Array.isArray(data.questions) ? data.questions : [];
        const answersPayload = Array.isArray(data.answers) ? data.answers : [];

        metaAnsweredBy.textContent = answered.username ? String(answered.username) : ("User #" + String(answered.user_id || ""));
        metaCompletedAt.textContent = answer.completed_at ? String(answer.completed_at) : "n/a";
        metaChecklistAuthor.textContent = author.user_name ? String(author.user_name) : ("User #" + String(author.user_id || ""));
        metaAnswerId.textContent = answer.id !== undefined && answer.id !== null ? String(answer.id) : "";

        checklistTitle.textContent = checklist.name ? String(checklist.name) : ("Checklist #" + String(checklist.id || ""));
        checklistDescription.textContent = checklist.description ? String(checklist.description) : "";

        document.title = "CheckD — " + checklistTitle.textContent;

        questionsTbody.innerHTML = "";
        for (let i = 0; i < questions.length; i += 1) {
            const q = questions[i];
            const qid = q && q.id !== undefined && q.id !== null ? Number(q.id) : NaN;
            const sel = !Number.isNaN(qid) ? answersForQuestion(answersPayload, qid) : [];
            questionsTbody.appendChild(renderQuestionRow(q, sel));
        }

        exportRoot.hidden = false;
    }

    async function main() {
        const answerId = parseAnswerIdFromUrl();
        if (answerId === null) {
            showStatus("Missing or invalid answer id. Use export-answer.html?id=<number>", false);
            return;
        }

        statusBox.innerHTML = "<p class=\"text-secondary small mb-0\">Loading…</p>";
        const res = await window.CheckD.config.apiCallPublic(
            "/export/answer?id=" + encodeURIComponent(String(answerId)),
            { method: "GET" }
        );

        statusBox.innerHTML = "";
        if (!res.ok || !res.data) {
            const err = res.data && res.data.error ? String(res.data.error) : (res.errorCode || "request_failed");
            showStatus("Failed to load export: " + err, false);
            return;
        }

        if (res.data.ok !== true) {
            const err = res.data.error ? String(res.data.error) : "unknown_error";
            showStatus(err, false);
            return;
        }

        renderSuccess(res.data);
    }

    main();
})();
