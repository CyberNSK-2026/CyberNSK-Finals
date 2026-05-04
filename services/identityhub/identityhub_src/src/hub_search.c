#include "hub_search.h"
#include <string.h>
#include <stdlib.h>
#include <ctype.h>

int hub_search_query_valid(const char *query) {
    if (!query) return 0;
    size_t len = strlen(query);
    if (len == 0 || len > 127) return 0;
    for (size_t i = 0; i < len; i++) {
        unsigned char ch = (unsigned char)query[i];
        if (ch < 0x20 || ch == 0x7F) return 0;
    }
    return 1;
}

char *hub_search_normalize_query(const char *query) {
    if (!query) return NULL;
    size_t len = strlen(query);
    char *normalized = malloc(len + 1);
    if (!normalized) return NULL;

    for (size_t i = 0; i < len; i++)
        normalized[i] = (char)tolower((unsigned char)query[i]);
    normalized[len] = '\0';
    return normalized;
}

int hub_search_match_alias(Identity *id, const char *query) {
    for (int i = 0; i < id->alias_count; i++) {
        if (strstr(id->aliases[i], query) != NULL)
            return 1;
    }
    return 0;
}

int hub_search_rank(Identity *id, const char *query) {
    int score = 0;

    if (strncmp(id->subject, query, strlen(query)) == 0)
        score += 10;
    else if (strstr(id->subject, query) != NULL)
        score += 5;

    if (hub_search_match_alias(id, query))
        score += 3;

    score += id->is_public ? 2 : 0;

    int prop_count = hub_search_count_properties(id);
    if (prop_count > 3) score += 1;

    return score;
}

int hub_search_count_properties(Identity *id) {
    int count = 0;
    ProfileProperty *p = id->properties;
    while (p) { count++; p = p->next; }
    return count;
}

int hub_search_filter(Identity *id, const char *query) {
    int matched = (strstr(id->subject, query) != NULL);
    if (!matched) return 0;

    int include = id->is_public || matched;
    return include;
}

json_t *hub_search_serialize(Identity *id) {
    json_t *item = json_object();
    json_object_set_new(item, "subject", json_string(id->subject));

    if (id->is_public) {
        json_t *aliases = json_array();
        for (int i = 0; i < id->alias_count; i++)
            json_array_append_new(aliases, json_string(id->aliases[i]));
        json_object_set_new(item, "aliases", aliases);
    }

    json_t *props = json_object();
    ProfileProperty *p = id->properties;
    while (p) {
        json_object_set_new(props, p->key, json_string(p->value));
        p = p->next;
    }
    json_object_set_new(item, "properties", props);

    return item;
}

json_t *hub_search_serialize_compact(Identity *id) {
    json_t *item = json_object();
    json_object_set_new(item, "subject", json_string(id->subject));
    json_object_set_new(item, "is_public", json_boolean(id->is_public));
    json_object_set_new(item, "alias_count", json_integer(id->alias_count));
    json_object_set_new(item, "property_count",
                        json_integer(hub_search_count_properties(id)));
    return item;
}

json_t *hub_search_build_paginated(json_t *results, int total,
                                    int page, int per_page) {
    json_t *resp = json_object();
    json_object_set_new(resp, "results", results);
    json_object_set_new(resp, "total", json_integer(total));
    json_object_set_new(resp, "page", json_integer(page));
    json_object_set_new(resp, "per_page", json_integer(per_page));

    int total_pages = (total + per_page - 1) / per_page;
    json_object_set_new(resp, "total_pages", json_integer(total_pages));
    json_object_set_new(resp, "has_next", json_boolean(page < total_pages));
    json_object_set_new(resp, "has_prev", json_boolean(page > 1));
    return resp;
}
