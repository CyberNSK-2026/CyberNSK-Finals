#include "cache.h"
#include <string.h>
#include <stdio.h>

static Identity *entries[CACHE_SIZE];
static int count = 0;

void cache_init(void) {
    memset(entries, 0, sizeof(entries));
    count = 0;
}

void cache_add(Identity *id) {
    
    for (int i = 0; i < count; i++) {
        if (entries[i] && entries[i]->id == id->id) {
            if (entries[i] != id) {
                identity_free(entries[i]);
                entries[i] = id;
            }
            Identity *tmp = entries[i];
            for (int j = i; j > 0; j--) entries[j] = entries[j-1];
            entries[0] = tmp;
            return;
        }
    }

    
    if (count >= CACHE_SIZE) {
        identity_free(entries[CACHE_SIZE - 1]);
        entries[CACHE_SIZE - 1] = NULL;
        count = CACHE_SIZE - 1;
    }

    
    for (int i = count; i > 0; i--) entries[i] = entries[i-1];
    entries[0] = id;
    count++;
}

Identity *cache_find_by_id(uint32_t id) {
    for (int i = 0; i < count; i++) {
        if (entries[i] && entries[i]->id == id) {
            
            Identity *tmp = entries[i];
            for (int j = i; j > 0; j--) entries[j] = entries[j-1];
            entries[0] = tmp;
            return tmp;
        }
    }
    return NULL;
}

Identity *cache_find_by_subject(const char *subject) {
    for (int i = 0; i < count; i++) {
        if (entries[i] && strcmp(entries[i]->subject, subject) == 0) {
            Identity *tmp = entries[i];
            for (int j = i; j > 0; j--) entries[j] = entries[j-1];
            entries[0] = tmp;
            return tmp;
        }
    }
    return NULL;
}

void cache_invalidate(uint32_t id) {
    for (int i = 0; i < count; i++) {
        if (entries[i] && entries[i]->id == id) {
            for (int j = i; j < count - 1; j++) entries[j] = entries[j+1];
            entries[count-1] = NULL;
            count--;
            return;
        }
    }
}
