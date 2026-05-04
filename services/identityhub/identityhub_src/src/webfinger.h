#ifndef WEBFINGER_H
#define WEBFINGER_H

#include "identity.h"
#include <jansson.h>

json_t *build_jrd_response(Identity *id, const char *rel_filter);

#endif
