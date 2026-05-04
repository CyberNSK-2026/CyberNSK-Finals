#ifndef IDENTITY_H
#define IDENTITY_H

#include <stdint.h>
#include <time.h>

#define MAX_SUBJECT 128
#define MAX_KEY 64
#define MAX_VALUE 256
#define MAX_REL 64
#define MAX_HREF 512
#define MAX_TYPE 32
#define MAX_ALIASES 10
#define MAX_ALIAS_LEN 128
#define MAX_SIGNATURE 512
#define MAX_PEM_KEY 4096
#define PASSWORD_HASH_LEN 32
#define DATA_DIR "/data/identities"

typedef struct ProfileProperty {
    char key[MAX_KEY];
    char value[MAX_VALUE];
    int is_signed;
    unsigned char signature[MAX_SIGNATURE];
    int signature_len;
    struct ProfileProperty *next;
} ProfileProperty;

typedef struct ProfileLink {
    char rel[MAX_REL];
    char href[MAX_HREF];
    char type[MAX_TYPE];
    struct ProfileLink *next;
} ProfileLink;

typedef struct Identity {
    uint32_t id;
    char subject[MAX_SUBJECT];
    unsigned char password_hash[PASSWORD_HASH_LEN];
    int is_public;
    time_t created_at;
    time_t updated_at;
    char aliases[MAX_ALIASES][MAX_ALIAS_LEN];
    int alias_count;
    ProfileProperty *properties;
    ProfileLink *links;
    char private_key[MAX_PEM_KEY];
    char public_key[MAX_PEM_KEY];
} Identity;

Identity *identity_create(const char *subject, const unsigned char *password_hash, int is_public);
void identity_free(Identity *id);
ProfileProperty *identity_add_property(Identity *id, const char *key, const char *value);
ProfileLink *identity_add_link(Identity *id, const char *rel, const char *href, const char *type);
int identity_add_alias(Identity *id, const char *alias);
ProfileProperty *identity_find_property(Identity *id, const char *key);

#endif
