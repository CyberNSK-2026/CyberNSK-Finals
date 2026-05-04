(function () {
    /** @type {HTMLFormElement | null} */
    const form = document.querySelector("form");
    /** @type {HTMLInputElement | null} */
    const usernameInput = document.getElementById("username");
    /** @type {HTMLInputElement | null} */
    const emailInput = document.getElementById("email");
    /** @type {HTMLInputElement | null} */
    const passInput = document.getElementById("pwd");

    if (!form || !usernameInput || !emailInput || !passInput) {
        return;
    }

    /**
     * @param {string} message
     * @param {string=} type
     */
    function showMessage(message, type) {
        const alertType = type || "danger";
        let alertEl = document.getElementById("register-message");
        if (!alertEl) {
            alertEl = document.createElement("div");
            alertEl.id = "register-message";
            alertEl.className = "alert mt-3 mb-3";
            form.appendChild(alertEl);
        }
        alertEl.className = "alert alert-" + alertType + " mt-3 mb-3";
        alertEl.textContent = message;
    }

    /**
     * @returns {void}
     */
    function clearMessage() {
        const alertEl = document.getElementById("register-message");
        if (alertEl) {
            alertEl.remove();
        }
    }

    form.addEventListener("submit", async function (event) {
        event.preventDefault();
        clearMessage();

        const username = usernameInput.value.trim();
        const email = emailInput.value.trim();
        const pass = passInput.value;

        if (!username || !email || !pass) {
            showMessage("Please fill username, email and password.");
            return;
        }

        const result = await window.CheckD.config.apiCallPublic("/auth/register", {
            method: "POST",
            body: {
                user: username,
                email: email,
                pass: pass,
            },
        });

        if (!result.ok || !result.data || result.data.ok !== true) {
            const serverError = result.data && result.data.error ? String(result.data.error) : "Registration failed.";
            showMessage(serverError);
            return;
        }

        if (result.data.token) {
            window.CheckD.config.storage.set(window.CheckD.config.STORAGE_KEYS.authToken, result.data.token);
            window.CheckD.config.storage.set(window.CheckD.config.STORAGE_KEYS.authTokenType, "Custom");
            window.location.href = "index.html";
            return;
        }

        showMessage("Registration complete. Please login.", "success");
        setTimeout(function () {
            window.location.href = "login.html";
        }, 700);
    });
})();
