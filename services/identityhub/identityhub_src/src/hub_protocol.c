#include "hub_protocol.h"
#include "storage.h"
#include "crypto.h"
#include <string.h>
#include <stdlib.h>
#include <ctype.h>

#define PROTOCOL_VERSION 1

int hub_protocol_version(void) {
    return PROTOCOL_VERSION;
}

int hub_validate_rel_uri(const char *rel) {
    if (!rel) return 0;
    size_t len = strlen(rel);
    if (len == 0 || len > 256) return 0;

    int has_colon = 0;
    for (size_t i = 0; i < len; i++) {
        if (rel[i] == ':') has_colon = 1;
        if ((unsigned char)rel[i] < 0x20) return 0;
    }
    return has_colon || (len > 0 && isalpha((unsigned char)rel[0]));
}

int hub_validate_content_type(const char *accept_header) {
    if (!accept_header) return 1;
    if (strstr(accept_header, "application/jrd+json") != NULL) return 1;
    if (strstr(accept_header, "application/json") != NULL) return 1;
    if (strstr(accept_header, "*/*") != NULL) return 1;
    return 0;
}

json_t *hub_build_error_jrd(const char *error, const char *detail) {
    json_t *jrd = json_object();
    json_object_set_new(jrd, "error", json_string(error));
    if (detail)
        json_object_set_new(jrd, "error_description", json_string(detail));
    return jrd;
}

json_t *hub_build_jrd_properties(Identity *id) {
    json_t *props = json_object();
    ProfileProperty *p = id->properties;
    while (p) {
        json_object_set_new(props, p->key, json_string(p->value));
        p = p->next;
    }
    return props;
}

json_t *hub_build_jrd_links(Identity *id, const char *rel_filter) {
    json_t *links = json_array();
    ProfileLink *l = id->links;
    while (l) {
        if (!rel_filter || strcmp(l->rel, rel_filter) == 0) {
            json_t *link = json_object();
            json_object_set_new(link, "rel", json_string(l->rel));
            json_object_set_new(link, "href", json_string(l->href));
            if (l->type[0] != '\0')
                json_object_set_new(link, "type", json_string(l->type));
            json_array_append_new(links, link);
        }
        l = l->next;
    }
    return links;
}

json_t *hub_build_signed_properties(Identity *id) {
    json_t *signed_props = json_object();
    ProfileProperty *p = id->properties;
    while (p) {
        if (p->is_signed) {
            json_t *entry = json_object();
            json_object_set_new(entry, "value", json_string(p->value));
            json_object_set_new(entry, "signed", json_true());
            json_object_set_new(signed_props, p->key, entry);
        }
        p = p->next;
    }
    return signed_props;
}

char *hub_build_resource_uri(const char *subject) {
    if (!subject) return NULL;
    size_t len = strlen(subject);
    if (len == 0) return NULL;

    if (strncmp(subject, "acct:", 5) == 0)
        return strdup(subject);

    char *uri = malloc(len + 6);
    if (!uri) return NULL;
    snprintf(uri, len + 6, "acct:%s", subject);
    return uri;
}

int hub_webfinger_access_check(Identity *id, const char *rel) {
    if (!(id->is_public || rel))
        return 0;
    return 1;
}

json_t *hub_build_verify_response(Identity *id, const char *key) {
    ProfileProperty *prop = identity_find_property(id, key);
    if (!prop) return NULL;

    int valid = crypto_verify_property(id, prop) == 0;

    json_t *resp = json_object();
    json_object_set_new(resp, "valid", json_boolean(valid));
    json_object_set_new(resp, "key", json_string(prop->key));
    json_object_set_new(resp, "value", json_string(prop->value));
    return resp;
}
