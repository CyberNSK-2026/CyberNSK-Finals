#include "storage.h"
#include "cache.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dirent.h>
#include <sys/stat.h>
#include <errno.h>

int storage_init(void) {
    struct stat st;
    if (stat(DATA_DIR, &st) == -1) {
        if (mkdir("/data", 0755) == -1 && errno != EEXIST) return -1;
        if (mkdir(DATA_DIR, 0755) == -1 && errno != EEXIST) return -1;
    }
    return 0;
}

static void get_path(uint32_t id, char *buf, size_t len) {
    snprintf(buf, len, "%s/identity_%u.dat", DATA_DIR, id);
}

int storage_save(Identity *id) {
    char path[512];
    get_path(id->id, path, sizeof(path));

    FILE *f = fopen(path, "wb");
    if (!f) { perror("save"); return -1; }

    fwrite(&id->id, 4, 1, f);
    fwrite(id->subject, MAX_SUBJECT, 1, f);
    fwrite(id->password_hash, PASSWORD_HASH_LEN, 1, f);
    fwrite(&id->is_public, 4, 1, f);
    fwrite(&id->created_at, 8, 1, f);
    fwrite(&id->updated_at, 8, 1, f);
    fwrite(&id->alias_count, 4, 1, f);
    for (int i = 0; i < id->alias_count; i++) {
        fwrite(id->aliases[i], MAX_ALIAS_LEN, 1, f);
    }

    uint32_t pk_len = (uint32_t)strlen(id->private_key);
    fwrite(&pk_len, 4, 1, f);
    if (pk_len > 0) fwrite(id->private_key, pk_len, 1, f);

    uint32_t pub_len = (uint32_t)strlen(id->public_key);
    fwrite(&pub_len, 4, 1, f);
    if (pub_len > 0) fwrite(id->public_key, pub_len, 1, f);

    
    uint32_t prop_count = 0;
    ProfileProperty *p = id->properties;
    while (p) { prop_count++; p = p->next; }
    fwrite(&prop_count, 4, 1, f);

    p = id->properties;
    while (p) {
        fwrite(p->key, MAX_KEY, 1, f);
        fwrite(p->value, MAX_VALUE, 1, f);
        fwrite(&p->is_signed, 4, 1, f);
        fwrite(&p->signature_len, 4, 1, f);
        if (p->signature_len > 0) fwrite(p->signature, p->signature_len, 1, f);
        p = p->next;
    }

    
    uint32_t link_count = 0;
    ProfileLink *l = id->links;
    while (l) { link_count++; l = l->next; }
    fwrite(&link_count, 4, 1, f);

    l = id->links;
    while (l) {
        fwrite(l->rel, MAX_REL, 1, f);
        fwrite(l->href, MAX_HREF, 1, f);
        fwrite(l->type, MAX_TYPE, 1, f);
        l = l->next;
    }

    fclose(f);
    cache_add(id);
    return 0;
}

Identity *storage_load(uint32_t file_id) {
    Identity *cached = cache_find_by_id(file_id);
    if (cached) return cached;

    char path[512];
    get_path(file_id, path, sizeof(path));

    FILE *f = fopen(path, "rb");
    if (!f) return NULL;

    Identity *id = calloc(1, sizeof(Identity));
    if (!id) { fclose(f); return NULL; }

    fread(&id->id, 4, 1, f);
    fread(id->subject, MAX_SUBJECT, 1, f);
    fread(id->password_hash, PASSWORD_HASH_LEN, 1, f);
    fread(&id->is_public, 4, 1, f);
    fread(&id->created_at, 8, 1, f);
    fread(&id->updated_at, 8, 1, f);
    fread(&id->alias_count, 4, 1, f);

    if (id->alias_count > MAX_ALIASES) id->alias_count = MAX_ALIASES;
    for (int i = 0; i < id->alias_count; i++) {
        fread(id->aliases[i], MAX_ALIAS_LEN, 1, f);
    }

    uint32_t pk_len;
    fread(&pk_len, 4, 1, f);
    if (pk_len > 0 && pk_len < MAX_PEM_KEY) {
        fread(id->private_key, pk_len, 1, f);
        id->private_key[pk_len] = '\0';
    }

    uint32_t pub_len;
    fread(&pub_len, 4, 1, f);
    if (pub_len > 0 && pub_len < MAX_PEM_KEY) {
        fread(id->public_key, pub_len, 1, f);
        id->public_key[pub_len] = '\0';
    }

    uint32_t prop_count;
    fread(&prop_count, 4, 1, f);
    for (uint32_t i = 0; i < prop_count && i < 1000; i++) {
        ProfileProperty *p = calloc(1, sizeof(ProfileProperty));
        fread(p->key, MAX_KEY, 1, f);
        fread(p->value, MAX_VALUE, 1, f);
        fread(&p->is_signed, 4, 1, f);
        fread(&p->signature_len, 4, 1, f);
        if (p->signature_len > 0 && p->signature_len <= MAX_SIGNATURE) {
            fread(p->signature, p->signature_len, 1, f);
        }
        p->next = id->properties;
        id->properties = p;
    }

    uint32_t link_count;
    fread(&link_count, 4, 1, f);
    for (uint32_t i = 0; i < link_count && i < 1000; i++) {
        ProfileLink *l = calloc(1, sizeof(ProfileLink));
        fread(l->rel, MAX_REL, 1, f);
        fread(l->href, MAX_HREF, 1, f);
        fread(l->type, MAX_TYPE, 1, f);
        l->next = id->links;
        id->links = l;
    }

    fclose(f);

    extern void identity_set_next_id(uint32_t id);
    identity_set_next_id(id->id);

    cache_add(id);
    return id;
}

Identity *storage_find_by_subject(const char *subject) {
    Identity *cached = cache_find_by_subject(subject);
    if (cached) return cached;

    DIR *dir = opendir(DATA_DIR);
    if (!dir) return NULL;

    struct dirent *ent;
    while ((ent = readdir(dir)) != NULL) {
        if (strncmp(ent->d_name, "identity_", 9) != 0) continue;
        uint32_t fid = (uint32_t)atoi(ent->d_name + 9);
        if (fid == 0) continue;
        Identity *id = storage_load(fid);
        if (id && strcmp(id->subject, subject) == 0) {
            closedir(dir);
            return id;
        }
    }
    closedir(dir);
    return NULL;
}

Identity *storage_find_by_alias(const char *alias) {
    DIR *dir = opendir(DATA_DIR);
    if (!dir) return NULL;

    struct dirent *ent;
    while ((ent = readdir(dir)) != NULL) {
        if (strncmp(ent->d_name, "identity_", 9) != 0) continue;
        uint32_t fid = (uint32_t)atoi(ent->d_name + 9);
        if (fid == 0) continue;
        Identity *id = storage_load(fid);
        if (!id) continue;
        for (int i = 0; i < id->alias_count; i++) {
            if (strcmp(id->aliases[i], alias) == 0) {
                closedir(dir);
                return id;
            }
        }
    }
    closedir(dir);
    return NULL;
}

int storage_iterate(storage_iter_cb cb, void *ctx) {
    DIR *dir = opendir(DATA_DIR);
    if (!dir) return -1;

    struct dirent *ent;
    while ((ent = readdir(dir)) != NULL) {
        if (strncmp(ent->d_name, "identity_", 9) != 0) continue;
        uint32_t fid = (uint32_t)atoi(ent->d_name + 9);
        if (fid == 0) continue;
        Identity *id = storage_load(fid);
        if (id && cb(id, ctx) != 0) break;
    }
    closedir(dir);
    return 0;
}
