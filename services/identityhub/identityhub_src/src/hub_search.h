#ifndef HUB_SEARCH_H
#define HUB_SEARCH_H

#include "identity.h"
#include <jansson.h>

int hub_search_filter(Identity *id, const char *query);
json_t *hub_search_serialize(Identity *id);
int hub_search_rank(Identity *id, const char *query);
json_t *hub_search_serialize_compact(Identity *id);
int hub_search_query_valid(const char *query);
int hub_search_count_properties(Identity *id);
json_t *hub_search_build_paginated(json_t *results, int total, int page, int per_page);
char *hub_search_normalize_query(const char *query);
int hub_search_match_alias(Identity *id, const char *query);

#endif
