#include "handlers.h"
#include "identity.h"
#include "storage.h"
#include "cache.h"
#include "crypto.h"
#include "webfinger.h"
#include "security.h"
#include "hub_auth.h"
#include "hub_search.h"
#include "hub_resolve.h"
#include "hub_protocol.h"
#include "hub_export.h"
#include <jansson.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>

static int send_json(struct MHD_Connection *c, int status, json_t *j) {
    char *body = json_dumps(j, JSON_COMPACT);
    json_decref(j);
    struct MHD_Response *r = MHD_create_response_from_buffer(
        strlen(body), body, MHD_RESPMEM_MUST_FREE);
    MHD_add_response_header(r, "Content-Type", "application/jrd+json");
    MHD_add_response_header(r, "Access-Control-Allow-Origin", "*");
    int ret = MHD_queue_response(c, status, r);
    MHD_destroy_response(r);
    return ret;
}

static int send_error(struct MHD_Connection *c, int status, const char *msg) {
    json_t *j = json_object();
    json_object_set_new(j, "error", json_string(msg));
    return send_json(c, status, j);
}

static int send_binary(struct MHD_Connection *c, void *data, size_t len,
                       const char *filename) {
    struct MHD_Response *r = MHD_create_response_from_buffer(len, data,
                                                              MHD_RESPMEM_MUST_FREE);
    MHD_add_response_header(r, "Content-Type", "application/octet-stream");
    char disp[256];
    snprintf(disp, sizeof(disp), "attachment; filename=%s", filename);
    MHD_add_response_header(r, "Content-Disposition", disp);
    int ret = MHD_queue_response(c, 200, r);
    MHD_destroy_response(r);
    return ret;
}

static int handle_create_identity(struct MHD_Connection *c, const char *body) {
    json_error_t err;
    json_t *root = json_loads(body, 0, &err);
    if (!root) return send_error(c, 400, "invalid JSON");

    const char *subject = json_string_value(json_object_get(root, "subject"));
    const char *password = json_string_value(json_object_get(root, "password"));
    json_t *j_public = json_object_get(root, "is_public");

    if (!subject || !password) {
        json_decref(root);
        return send_error(c, 400, "subject and password required");
    }

    if (!sanitize_subject(subject) || !hub_check_subject_format(subject)) {
        json_decref(root);
        return send_error(c, 400, "invalid subject format");
    }

    if (!sanitize_input(password, 128) ||
        hub_validate_password_strength(password) < 1) {
        json_decref(root);
        return send_error(c, 400, "invalid password");
    }

    if (storage_find_by_subject(subject)) {
        json_decref(root);
        return send_error(c, 409, "subject already exists");
    }

    unsigned char hash[PASSWORD_HASH_LEN];
    crypto_hash_password(password, hash);

    int is_public = j_public ? json_is_true(j_public) : 1;

    Identity *id = identity_create(subject, hash, is_public);
    if (!id) {
        json_decref(root);
        return send_error(c, 500, "failed to create identity");
    }

    if (crypto_generate_rsa_keypair(id) != 0) {
        identity_free(id);
        json_decref(root);
        return send_error(c, 500, "failed to generate keypair");
    }

    if (storage_save(id) != 0) {
        identity_free(id);
        json_decref(root);
        return send_error(c, 500, "failed to save identity");
    }

    json_t *resp = json_object();
    json_object_set_new(resp, "id", json_integer(id->id));
    json_object_set_new(resp, "subject", json_string(id->subject));
    json_object_set_new(resp, "is_public", json_boolean(id->is_public));
    json_object_set_new(resp, "public_key", json_string(id->public_key));

    json_decref(root);
    return send_json(c, 201, resp);
}

static int handle_add_property(struct MHD_Connection *c, const char *body) {
    json_error_t err;
    json_t *root = json_loads(body, 0, &err);
    if (!root) return send_error(c, 400, "invalid JSON");

    const char *subject = json_string_value(json_object_get(root, "subject"));
    const char *password = json_string_value(json_object_get(root, "password"));
    const char *key = json_string_value(json_object_get(root, "key"));
    const char *value = json_string_value(json_object_get(root, "value"));
    int do_sign = json_is_true(json_object_get(root, "sign"));

    if (!subject || !password || !key || !value) {
        json_decref(root);
        return send_error(c, 400, "subject, password, key, value required");
    }

    if (!sanitize_subject(subject) || !sanitize_key(key) || !sanitize_value(value)) {
        json_decref(root);
        return send_error(c, 400, "invalid input");
    }

    Identity *id = storage_find_by_subject(subject);
    if (!id) { json_decref(root); return send_error(c, 404, "identity not found"); }

    if (!hub_verify_credentials(id->password_hash, password)) {
        json_decref(root);
        return send_error(c, 403, "wrong password");
    }

    ProfileProperty *prop = identity_add_property(id, key, value);
    if (do_sign) crypto_sign_property(id, prop);
    storage_save(id);

    json_t *resp = json_object();
    json_object_set_new(resp, "ok", json_true());
    json_object_set_new(resp, "key", json_string(prop->key));
    json_object_set_new(resp, "is_signed", json_boolean(prop->is_signed));

    json_decref(root);
    return send_json(c, 200, resp);
}

static int handle_add_link(struct MHD_Connection *c, const char *body) {
    json_error_t err;
    json_t *root = json_loads(body, 0, &err);
    if (!root) return send_error(c, 400, "invalid JSON");

    const char *subject = json_string_value(json_object_get(root, "subject"));
    const char *password = json_string_value(json_object_get(root, "password"));
    const char *rel = json_string_value(json_object_get(root, "rel"));
    const char *href = json_string_value(json_object_get(root, "href"));
    const char *type = json_string_value(json_object_get(root, "type"));

    if (!subject || !password || !rel || !href) {
        json_decref(root);
        return send_error(c, 400, "subject, password, rel, href required");
    }

    if (!sanitize_subject(subject) || !sanitize_rel(rel) || !sanitize_href(href)) {
        json_decref(root);
        return send_error(c, 400, "invalid input");
    }

    Identity *id = storage_find_by_subject(subject);
    if (!id) { json_decref(root); return send_error(c, 404, "identity not found"); }

    if (!hub_verify_credentials(id->password_hash, password)) {
        json_decref(root);
        return send_error(c, 403, "wrong password");
    }

    identity_add_link(id, rel, href, type);
    storage_save(id);

    json_t *resp = json_object();
    json_object_set_new(resp, "ok", json_true());
    json_decref(root);
    return send_json(c, 200, resp);
}

static int handle_add_alias(struct MHD_Connection *c, const char *body) {
    json_error_t err;
    json_t *root = json_loads(body, 0, &err);
    if (!root) return send_error(c, 400, "invalid JSON");

    const char *subject = json_string_value(json_object_get(root, "subject"));
    const char *password = json_string_value(json_object_get(root, "password"));
    const char *alias = json_string_value(json_object_get(root, "alias"));

    if (!subject || !password || !alias) {
        json_decref(root);
        return send_error(c, 400, "subject, password, alias required");
    }

    if (!sanitize_subject(subject) || !sanitize_input(alias, MAX_ALIAS_LEN - 1)) {
        json_decref(root);
        return send_error(c, 400, "invalid input");
    }

    Identity *id = storage_find_by_subject(subject);
    if (!id) { json_decref(root); return send_error(c, 404, "identity not found"); }

    if (!hub_verify_credentials(id->password_hash, password)) {
        json_decref(root);
        return send_error(c, 403, "wrong password");
    }

    if (identity_add_alias(id, alias) != 0) {
        json_decref(root);
        return send_error(c, 400, "max aliases reached");
    }

    storage_save(id);

    json_t *resp = json_object();
    json_object_set_new(resp, "ok", json_true());
    json_decref(root);
    return send_json(c, 200, resp);
}

static int handle_sign_property(struct MHD_Connection *c, const char *body) {
    json_error_t err;
    json_t *root = json_loads(body, 0, &err);
    if (!root) return send_error(c, 400, "invalid JSON");

    const char *subject = json_string_value(json_object_get(root, "subject"));
    const char *password = json_string_value(json_object_get(root, "password"));
    const char *key = json_string_value(json_object_get(root, "key"));

    if (!subject || !password || !key) {
        json_decref(root);
        return send_error(c, 400, "subject, password, key required");
    }

    if (!sanitize_subject(subject) || !sanitize_key(key)) {
        json_decref(root);
        return send_error(c, 400, "invalid input");
    }

    Identity *id = storage_find_by_subject(subject);
    if (!id) { json_decref(root); return send_error(c, 404, "identity not found"); }

    if (!hub_verify_credentials(id->password_hash, password)) {
        json_decref(root);
        return send_error(c, 403, "wrong password");
    }

    ProfileProperty *prop = identity_find_property(id, key);
    if (!prop) { json_decref(root); return send_error(c, 404, "property not found"); }

    if (crypto_sign_property(id, prop) != 0) {
        json_decref(root);
        return send_error(c, 500, "signing failed");
    }
    storage_save(id);

    json_t *resp = json_object();
    json_object_set_new(resp, "ok", json_true());
    json_object_set_new(resp, "is_signed", json_true());
    json_decref(root);
    return send_json(c, 200, resp);
}

static int handle_verify_property(struct MHD_Connection *c, const char *body) {
    json_error_t err;
    json_t *root = json_loads(body, 0, &err);
    if (!root) return send_error(c, 400, "invalid JSON");

    const char *subject = json_string_value(json_object_get(root, "subject"));
    const char *key = json_string_value(json_object_get(root, "key"));

    if (!subject || !key) {
        json_decref(root);
        return send_error(c, 400, "subject and key required");
    }

    if (!sanitize_subject(subject) || !sanitize_key(key)) {
        json_decref(root);
        return send_error(c, 400, "invalid input");
    }

    Identity *id = storage_find_by_subject(subject);
    if (!id) { json_decref(root); return send_error(c, 404, "identity not found"); }

    json_t *resp = hub_build_verify_response(id, key);
    if (!resp) { json_decref(root); return send_error(c, 404, "property not found"); }

    json_decref(root);
    return send_json(c, 200, resp);
}

static int handle_public_key(struct MHD_Connection *c) {
    const char *subject = MHD_lookup_connection_value(c, MHD_GET_ARGUMENT_KIND, "subject");
    if (!subject) return send_error(c, 400, "subject parameter required");

    if (!sanitize_input(subject, MAX_SUBJECT - 1) ||
        !hub_resolve_validate_uri(subject))
        return send_error(c, 400, "invalid subject");

    Identity *target = hub_resolve_identity(subject);
    if (!target) return send_error(c, 404, "identity not found");

    json_t *resp = json_object();
    json_object_set_new(resp, "subject", json_string(target->subject));
    json_object_set_new(resp, "public_key", json_string(target->public_key));

    json_t *props = json_object();
    ProfileProperty *p = target->properties;
    while (p) {
        json_object_set_new(props, p->key, json_string(p->value));
        p = p->next;
    }
    json_object_set_new(resp, "properties", props);

    return send_json(c, 200, resp);
}

struct search_ctx {
    const char *query;
    json_t *results;
    int count;
    int max_results;
};

static int search_cb(Identity *id, void *ctx) {
    struct search_ctx *s = ctx;
    if (s->count >= s->max_results) return 1;

    if (!hub_search_filter(id, s->query)) return 0;

    json_t *item = hub_search_serialize(id);
    json_array_append_new(s->results, item);
    s->count++;
    return 0;
}

static int handle_search(struct MHD_Connection *c) {
    const char *query = MHD_lookup_connection_value(c, MHD_GET_ARGUMENT_KIND, "query");
    if (!query) return send_error(c, 400, "query parameter required");

    if (!sanitize_input(query, MAX_SUBJECT - 1) ||
        !hub_search_query_valid(query))
        return send_error(c, 400, "invalid query");

    struct search_ctx ctx = {
        .query = query,
        .results = json_array(),
        .count = 0,
        .max_results = 50
    };

    storage_iterate(search_cb, &ctx);

    json_t *resp = json_object();
    json_object_set_new(resp, "results", ctx.results);
    json_object_set_new(resp, "count", json_integer(ctx.count));
    return send_json(c, 200, resp);
}

static int handle_webfinger(struct MHD_Connection *c) {
    const char *resource = MHD_lookup_connection_value(c, MHD_GET_ARGUMENT_KIND, "resource");
    if (!resource) return send_error(c, 400, "resource parameter required");

    if (!sanitize_input(resource, MAX_SUBJECT - 1))
        return send_error(c, 400, "invalid resource");

    Identity *id = storage_find_by_subject(resource);
    if (!id) return send_error(c, 404, "resource not found");

    const char *rel = MHD_lookup_connection_value(c, MHD_GET_ARGUMENT_KIND, "rel");
    if (rel && !sanitize_rel(rel))
        return send_error(c, 400, "invalid rel parameter");

    if (!hub_webfinger_access_check(id, rel))
        return send_error(c, 404, "resource not found");

    json_t *jrd = build_jrd_response(id, rel);
    return send_json(c, 200, jrd);
}

static int handle_export(struct MHD_Connection *c) {
    const char *id_str = MHD_lookup_connection_value(c, MHD_GET_ARGUMENT_KIND, "id");
    const char *subject = MHD_lookup_connection_value(c, MHD_GET_ARGUMENT_KIND, "subject");

    if (!id_str || !subject)
        return send_error(c, 400, "id and subject required");

    if (!sanitize_subject(subject))
        return send_error(c, 400, "invalid subject");

    uint32_t fid = (uint32_t)atoi(id_str);
    if (fid == 0) return send_error(c, 400, "invalid id");

    Identity *id = storage_load(fid);
    if (!id) return send_error(c, 404, "identity not found");

    if (!hub_export_check_access(id, subject))
        return send_error(c, 403, "access denied");

    char path[512];
    snprintf(path, sizeof(path), "%s/identity_%u.dat", DATA_DIR, fid);

    if (!hub_export_validate_path(path))
        return send_error(c, 400, "invalid export path");

    FILE *f = fopen(path, "rb");
    if (!f) return send_error(c, 404, "file not found");

    fseek(f, 0, SEEK_END);
    long size = ftell(f);
    fseek(f, 0, SEEK_SET);

    if (size <= 0 || size > 1024 * 1024) {
        fclose(f);
        return send_error(c, 500, "invalid file");
    }

    char *buf = malloc(size);
    fread(buf, 1, size, f);
    fclose(f);

    return send_binary(c, buf, size, "identity.dat");
}

int handle_request(void *cls, struct MHD_Connection *connection,
                   const char *url, const char *method,
                   const char *version, const char *upload_data,
                   size_t *upload_data_size, void **con_cls)
{
    (void)cls; (void)version;

    if (*con_cls == NULL) {
        struct PostContext *pc = calloc(1, sizeof(struct PostContext));
        *con_cls = pc;
        return MHD_YES;
    }

    struct PostContext *pc = *con_cls;

    if (*upload_data_size > 0) {
        if (pc->size + *upload_data_size > 65536) {
            *upload_data_size = 0;
            free(pc->data);
            free(pc);
            *con_cls = NULL;
            return send_error(connection, 413, "request too large");
        }
        pc->data = realloc(pc->data, pc->size + *upload_data_size + 1);
        memcpy(pc->data + pc->size, upload_data, *upload_data_size);
        pc->size += *upload_data_size;
        pc->data[pc->size] = '\0';
        *upload_data_size = 0;
        return MHD_YES;
    }

    int ret;

    if (strcmp(method, "GET") == 0) {
        if (strcmp(url, "/.well-known/webfinger") == 0) {
            ret = handle_webfinger(connection);
        } else if (strcmp(url, "/api/public_key") == 0) {
            ret = handle_public_key(connection);
        } else if (strcmp(url, "/api/search") == 0) {
            ret = handle_search(connection);
        } else if (strcmp(url, "/api/export") == 0) {
            ret = handle_export(connection);
        } else {
            ret = send_error(connection, 404, "not found");
        }
    } else if (strcmp(method, "POST") == 0) {
        if (!pc->data) {
            ret = send_error(connection, 400, "empty body");
        } else if (strcmp(url, "/api/create_identity") == 0) {
            ret = handle_create_identity(connection, pc->data);
        } else if (strcmp(url, "/api/add_property") == 0) {
            ret = handle_add_property(connection, pc->data);
        } else if (strcmp(url, "/api/add_link") == 0) {
            ret = handle_add_link(connection, pc->data);
        } else if (strcmp(url, "/api/add_alias") == 0) {
            ret = handle_add_alias(connection, pc->data);
        } else if (strcmp(url, "/api/sign_property") == 0) {
            ret = handle_sign_property(connection, pc->data);
        } else if (strcmp(url, "/api/verify_property") == 0) {
            ret = handle_verify_property(connection, pc->data);
        } else {
            ret = send_error(connection, 404, "not found");
        }
    } else {
        ret = send_error(connection, 405, "method not allowed");
    }

    free(pc->data);
    free(pc);
    *con_cls = NULL;

    return ret;
}
