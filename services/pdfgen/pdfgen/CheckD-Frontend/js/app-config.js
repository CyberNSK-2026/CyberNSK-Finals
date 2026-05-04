(function () {
    /**
     * @typedef {Object} ApiCallOptions
     * @property {string=} method
     * @property {Object.<string, string>=} headers
     * @property {*=} body
     */

    /**
     * @typedef {Object} ApiResult
     * @property {boolean} ok
     * @property {number} status
     * @property {string} errorCode
     * @property {*} data
     */

    /** @type {{authToken: string, authTokenType: string, authUser: string}} */
    const STORAGE_KEYS = {
        authToken: "checkd.auth.token",
        authTokenType: "checkd.auth.tokenType",
        authUser: "checkd.auth.user",
        editorBootstrap: "checkd.editor.bootstrap",
    };

    /**
     * Same host/port as the page, path `/api` (reverse-proxy / gateway).
     * For file:// opens use localhost fallback so dev still works.
     * @returns {string}
     */
    function getApiBaseUrl() {
        try {
            if (typeof window === "undefined" || !window.location) {
                return "http://localhost:8081/api";
            }
            if (window.location.protocol === "file:") {
                return "http://localhost:8081/api";
            }
            const origin = window.location.origin;
            if (origin && origin !== "null") {
                return origin.replace(/\/$/, "") + "/api";
            }
        } catch (error) {
            /* ignore */
        }
        return "http://localhost:8081/api";
    }

    /** @type {{get baseUrl(): string, timeoutMs: number}} */
    const API_CONFIG = {
        get baseUrl() {
            return getApiBaseUrl();
        },
        timeoutMs: 15000,
    };

    /** @type {{UNKNOWN: string, UNAUTHORIZED: string, BAD_DATA: string, FORBIDDEN: string, NOT_FOUND: string, CONFLICT: string, SERVER_ERROR: string, NETWORK_ERROR: string, TIMEOUT: string}} */
    const API_ERROR = {
        UNKNOWN: "unknown",
        UNAUTHORIZED: "unauthorized",
        BAD_DATA: "bad_data",
        FORBIDDEN: "forbidden",
        NOT_FOUND: "not_found",
        CONFLICT: "conflict",
        SERVER_ERROR: "server_error",
        NETWORK_ERROR: "network_error",
        TIMEOUT: "timeout",
    };

    /** @type {{get: function(string, *=): *, set: function(string, *): void, remove: function(string): void, clearAuth: function(): void}} */
    const storage = {
        get: function (key, fallbackValue) {
            const raw = localStorage.getItem(key);
            if (raw === null) {
                return fallbackValue === undefined ? null : fallbackValue;
            }
            try {
                return JSON.parse(raw);
            } catch (error) {
                return raw;
            }
        },
        set: function (key, value) {
            const stored = typeof value === "string" ? value : JSON.stringify(value);
            localStorage.setItem(key, stored);
        },
        remove: function (key) {
            localStorage.removeItem(key);
        },
        clearAuth: function () {
            localStorage.removeItem(STORAGE_KEYS.authToken);
            localStorage.removeItem(STORAGE_KEYS.authTokenType);
            localStorage.removeItem(STORAGE_KEYS.authUser);
        },
    };

    /**
     * @param {string=} path
     * @returns {string}
     */
    function buildApiUrl(path) {
        if (!path) {
            return API_CONFIG.baseUrl;
        }
        if (/^https?:\/\//i.test(path)) {
            return path;
        }
        const normalizedPath = path.charAt(0) === "/" ? path : "/" + path;
        return API_CONFIG.baseUrl + normalizedPath;
    }

    /**
     * @param {number} status
     * @returns {string}
     */
    function mapStatusToErrorCode(status) {
        if (status === 400) {
            return API_ERROR.BAD_DATA;
        }
        if (status === 401) {
            return API_ERROR.UNAUTHORIZED;
        }
        if (status === 403) {
            return API_ERROR.FORBIDDEN;
        }
        if (status === 404) {
            return API_ERROR.NOT_FOUND;
        }
        if (status === 409) {
            return API_ERROR.CONFLICT;
        }
        if (status >= 500) {
            return API_ERROR.SERVER_ERROR;
        }
        return API_ERROR.UNKNOWN;
    }

    /**
     * @param {Object.<string, string>} headers
     * @returns {Object.<string, string>}
     */
    function withAuthHeader(headers) {
        const token = storage.get(STORAGE_KEYS.authToken, "");
        if (!token) {
            return headers;
        }
        const tokenType = storage.get(STORAGE_KEYS.authTokenType, "Bearer");
        headers.Authorization = tokenType + " " + token;
        return headers;
    }

    /**
     * @param {Response} response
     * @returns {Promise<ApiResult>}
     */
    async function parseResponse(response) {
        const text = await response.text();
        let data = null;

        if (text) {
            try {
                data = JSON.parse(text);
            } catch (error) {
                data = text;
            }
        }

        return {
            ok: response.ok,
            status: response.status,
            errorCode: response.ok ? "" : mapStatusToErrorCode(response.status),
            data: data,
        };
    }

    /**
     * @param {string} path
     * @param {ApiCallOptions=} options
     * @param {boolean} withAuth
     * @returns {Promise<ApiResult>}
     */
    async function executeRequest(path, options, withAuth) {
        /** @type {ApiCallOptions} */
        const opts = options || {};
        /** @type {Object.<string, string>} */
        const headers = Object.assign({}, opts.headers || {});

        if (withAuth) {
            withAuthHeader(headers);
        }

        if (opts.body && !headers["Content-Type"]) {
            headers["Content-Type"] = "application/json";
        }

        let body = opts.body;
        if (body && headers["Content-Type"] === "application/json" && typeof body !== "string") {
            body = JSON.stringify(body);
        }

        const controller = new AbortController();
        const timerId = setTimeout(function () {
            controller.abort();
        }, API_CONFIG.timeoutMs);

        try {
            const response = await fetch(buildApiUrl(path), {
                method: opts.method || "GET",
                headers: headers,
                body: body,
                signal: controller.signal,
            });
            return await parseResponse(response);
        } catch (error) {
            if (error && error.name === "AbortError") {
                return {
                    ok: false,
                    status: 0,
                    errorCode: API_ERROR.TIMEOUT,
                    data: null,
                };
            }
            return {
                ok: false,
                status: 0,
                errorCode: API_ERROR.NETWORK_ERROR,
                data: null,
            };
        } finally {
            clearTimeout(timerId);
        }
    }

    /**
     * Auth-required API helper.
     * If token is missing, immediately returns UNAUTHORIZED without network call.
     *
     * @param {string} path
     * @param {ApiCallOptions=} options
     * @returns {Promise<ApiResult>}
     */
    async function apiCall(path, options) {
        const token = storage.get(STORAGE_KEYS.authToken, "");
        if (!token) {
            return {
                ok: false,
                status: 401,
                errorCode: API_ERROR.UNAUTHORIZED,
                data: null,
            };
        }
        return await executeRequest(path, options, true);
    }

    /**
     * Public API helper for unauthenticated requests (e.g. login/register).
     *
     * @param {string} path
     * @param {ApiCallOptions=} options
     * @returns {Promise<ApiResult>}
     */
    async function apiCallPublic(path, options) {
        return await executeRequest(path, options, false);
    }

    window.CheckD = window.CheckD || {};
    window.CheckD.config = {
        API_CONFIG: API_CONFIG,
        API_ERROR: API_ERROR,
        STORAGE_KEYS: STORAGE_KEYS,
        storage: storage,
        getApiBaseUrl: getApiBaseUrl,
        buildApiUrl: buildApiUrl,
        apiCall: apiCall,
        apiCallPublic: apiCallPublic,
    };
})();
