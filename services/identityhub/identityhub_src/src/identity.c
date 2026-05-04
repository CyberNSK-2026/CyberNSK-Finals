#include "identity.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

static uint32_t next_id = 1;

Identity *identity_create(const char *subject, const unsigned char *password_hash, int is_public) {
    Identity *id = calloc(1, sizeof(Identity));
    if (!id) return NULL;

    id->id = next_id++;
    strncpy(id->subject, subject, MAX_SUBJECT - 1);
    memcpy(id->password_hash, password_hash, PASSWORD_HASH_LEN);
    id->is_public = is_public;
    id->created_at = time(NULL);
    id->updated_at = id->created_at;
    id->alias_count = 0;
    id->properties = NULL;
    id->links = NULL;
    id->private_key[0] = '\0';
    id->public_key[0] = '\0';

    return id;
}

void identity_free(Identity *id) {
    if (!id) return;

    ProfileProperty *p = id->properties;
    while (p) {
        ProfileProperty *next = p->next;
        free(p);
        p = next;
    }

    ProfileLink *l = id->links;
    while (l) {
        ProfileLink *next = l->next;
        free(l);
        l = next;
    }

    free(id);
}

ProfileProperty *identity_add_property(Identity *id, const char *key, const char *value) {
    ProfileProperty *prop = calloc(1, sizeof(ProfileProperty));
    if (!prop) return NULL;

    strncpy(prop->key, key, MAX_KEY - 1);
    strncpy(prop->value, value, MAX_VALUE - 1);
    prop->is_signed = 0;
    prop->signature_len = 0;
    prop->next = id->properties;
    id->properties = prop;
    id->updated_at = time(NULL);

    return prop;
}

ProfileLink *identity_add_link(Identity *id, const char *rel, const char *href, const char *type) {
    ProfileLink *link = calloc(1, sizeof(ProfileLink));
    if (!link) return NULL;

    strncpy(link->rel, rel, MAX_REL - 1);
    strncpy(link->href, href, MAX_HREF - 1);
    if (type) strncpy(link->type, type, MAX_TYPE - 1);
    link->next = id->links;
    id->links = link;
    id->updated_at = time(NULL);

    return link;
}

int identity_add_alias(Identity *id, const char *alias) {
    if (id->alias_count >= MAX_ALIASES) return -1;
    strncpy(id->aliases[id->alias_count], alias, MAX_ALIAS_LEN - 1);
    id->alias_count++;
    id->updated_at = time(NULL);
    return 0;
}

ProfileProperty *identity_find_property(Identity *id, const char *key) {
    ProfileProperty *p = id->properties;
    while (p) {
        if (strcmp(p->key, key) == 0) return p;
        p = p->next;
    }
    return NULL;
}

void identity_set_next_id(uint32_t id) {
    if (id >= next_id) next_id = id + 1;
}
