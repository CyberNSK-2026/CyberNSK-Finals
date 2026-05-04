(function () {
    /** @type {HTMLFormElement | null} */
    const form = document.querySelector("form");
    /** @type {HTMLInputElement | null} */
    const userInput = document.getElementById("email");
    /** @type {HTMLInputElement | null} */
    const passInput = document.getElementById("pwd");

    if (!form || !userInput || !passInput) {
        return;
    }

    /**
     * @param {string} message
     */
    function showError(message) {
        let alertEl = document.getElementById("login-error");
        if (!alertEl) {
            alertEl = document.createElement("div");
            alertEl.id = "login-error";
            alertEl.className = "alert alert-danger mt-3 mb-3";
            form.appendChild(alertEl);
        }
        alertEl.textContent = message;
    }

    /**
     * @returns {void}
     */
    function clearError() {
        const alertEl = document.getElementById("login-error");
        if (alertEl) {
            alertEl.remove();
        }
    }

    form.addEventListener("submit", async function (event) {
        event.preventDefault();
        clearError();

        const email = userInput.value.trim();
        const pass = passInput.value;

        if (!email || !pass) {
            showError("Please provide both email and password.");
            return;
        }

        const result = await window.CheckD.config.apiCallPublic("/auth/login", {
            method: "POST",
            body: {
                email: email,
                pass: pass,
            },
        });

        if (!result.ok || !result.data || result.data.ok !== true || !result.data.token) {
            const serverError = result.data && result.data.error ? String(result.data.error) : "Login failed.";
            showError(serverError);
            return;
        }

        window.CheckD.config.storage.set(window.CheckD.config.STORAGE_KEYS.authToken, result.data.token);
        window.CheckD.config.storage.set(window.CheckD.config.STORAGE_KEYS.authTokenType, "Custom");
        window.location.href = "index.html";
    });
})();
