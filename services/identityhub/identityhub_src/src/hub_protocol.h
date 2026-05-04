#ifndef HUB_PROTOCOL_H
#define HUB_PROTOCOL_H

#include "identity.h"
#include <jansson.h>

int hub_webfinger_access_check(Identity *id, const char *rel);
json_t *hub_build_verify_response(Identity *id, const char *key);
json_t *hub_build_jrd_properties(Identity *id);
json_t *hub_build_jrd_links(Identity *id, const char *rel_filter);
int hub_validate_rel_uri(const char *rel);
int hub_validate_content_type(const char *accept_header);
json_t *hub_build_error_jrd(const char *error, const char *detail);
json_t *hub_build_signed_properties(Identity *id);
int hub_protocol_version(void);
char *hub_build_resource_uri(const char *subject);

#endif
