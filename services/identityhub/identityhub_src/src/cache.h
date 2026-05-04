#ifndef CACHE_H
#define CACHE_H

#include "identity.h"

#define CACHE_SIZE 10000

void cache_init(void);
void cache_add(Identity *id);
Identity *cache_find_by_id(uint32_t id);
Identity *cache_find_by_subject(const char *subject);
void cache_invalidate(uint32_t id);

#endif
