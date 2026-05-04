#ifndef STORAGE_H
#define STORAGE_H

#include "identity.h"

int storage_init(void);
int storage_save(Identity *id);
Identity *storage_load(uint32_t id);
Identity *storage_find_by_subject(const char *subject);
Identity *storage_find_by_alias(const char *alias);

typedef int (*storage_iter_cb)(Identity *id, void *ctx);
int storage_iterate(storage_iter_cb cb, void *ctx);

#endif
