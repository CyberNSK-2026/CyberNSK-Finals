#ifndef HUB_RESOLVE_H
#define HUB_RESOLVE_H

#include "identity.h"
#include <jansson.h>

Identity *hub_resolve_identity(const char *query);
Identity *hub_resolve_by_alias_only(const char *alias);
int hub_resolve_is_federated(const char *subject);
char *hub_resolve_extract_domain(const char *subject);
char *hub_resolve_extract_localpart(const char *subject);
int hub_resolve_validate_uri(const char *uri);
json_t *hub_resolve_build_response(Identity *id);
int hub_resolve_compare_domains(const char *subject1, const char *subject2);

#endif
