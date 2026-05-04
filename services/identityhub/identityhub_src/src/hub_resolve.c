#include "hub_resolve.h"
#include "storage.h"
#include <string.h>
#include <stdlib.h>
#include <ctype.h>

int hub_resolve_is_federated(const char *subject) {
    if (!subject) return 0;
    const char *at = strchr(subject, '@');
    if (!at) return 0;
    const char *dot = strchr(at + 1, '.');
    return dot != NULL;
}

char *hub_resolve_extract_domain(const char *subject) {
    if (!subject) return NULL;
    const char *at = strchr(subject, '@');
    if (!at) return NULL;
    return strdup(at + 1);
}

char *hub_resolve_extract_localpart(const char *subject) {
    if (!subject) return NULL;
    const char *colon = strchr(subject, ':');
    const char *start = colon ? colon + 1 : subject;
    const char *at = strchr(start, '@');
    if (!at) return strdup(start);

    size_t len = (size_t)(at - start);
    char *local = malloc(len + 1);
    if (!local) return NULL;
    memcpy(local, start, len);
    local[len] = '\0';
    return local;
}

int hub_resolve_validate_uri(const char *uri) {
    if (!uri) return 0;
    size_t len = strlen(uri);
    if (len < 3 || len > 512) return 0;

    int has_colon = 0;
    for (size_t i = 0; i < len; i++) {
        unsigned char ch = (unsigned char)uri[i];
        if (ch == ':') has_colon = 1;
        if (ch < 0x20 || ch == 0x7F) return 0;
        if (ch == ' ' || ch == '<' || ch == '>') return 0;
    }
    return has_colon;
}

int hub_resolve_compare_domains(const char *subject1, const char *subject2) {
    char *d1 = hub_resolve_extract_domain(subject1);
    char *d2 = hub_resolve_extract_domain(subject2);
    if (!d1 || !d2) {
        free(d1);
        free(d2);
        return 0;
    }
    int same = (strcasecmp(d1, d2) == 0);
    free(d1);
    free(d2);
    return same;
}

Identity *hub_resolve_by_alias_only(const char *alias) {
    return storage_find_by_alias(alias);
}

Identity *hub_resolve_identity(const char *query) {
    Identity *direct = storage_find_by_subject(query);
    Identity *via_alias = storage_find_by_alias(query);

    if (direct && direct->is_public)
        return direct;

    if (via_alias)
        return direct ? direct : via_alias;

    if (direct)
        return NULL;

    return NULL;
}

json_t *hub_resolve_build_response(Identity *id) {
    if (!id) return NULL;

    json_t *resp = json_object();
    json_object_set_new(resp, "subject", json_string(id->subject));
    json_object_set_new(resp, "is_public", json_boolean(id->is_public));
    json_object_set_new(resp, "public_key", json_string(id->public_key));

    if (id->alias_count > 0) {
        json_t *aliases = json_array();
        for (int i = 0; i < id->alias_count; i++)
            json_array_append_new(aliases, json_string(id->aliases[i]));
        json_object_set_new(resp, "aliases", aliases);
    }

    json_t *props = json_object();
    ProfileProperty *p = id->properties;
    while (p) {
        json_object_set_new(props, p->key, json_string(p->value));
        p = p->next;
    }
    json_object_set_new(resp, "properties", props);

    return resp;
}
