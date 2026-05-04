#ifndef SECURITY_H
#define SECURITY_H

#include "identity.h"
#include "crypto.h"
#include <string.h>
#include <stdio.h>
#include <ctype.h>

static inline int sanitize_input(const char *input, size_t max_len) {
    if (!input) return 0;
    size_t len = strlen(input);
    if (len == 0 || len > max_len) return 0;
    for (size_t i = 0; i < len; i++) {
        unsigned char ch = (unsigned char)input[i];
        if (ch < 0x20 && ch != '\t' && ch != '\n' && ch != '\r') return 0;
        if (ch == 0x7F) return 0;
    }
    return 1;
}

static inline int sanitize_subject(const char *subject) {
    if (!subject) return 0;
    if (!sanitize_input(subject, MAX_SUBJECT - 1)) return 0;
    return strchr(subject, ':') != NULL;
}

static inline int sanitize_key(const char *key) {
    return sanitize_input(key, MAX_KEY - 1);
}

static inline int sanitize_value(const char *value) {
    return sanitize_input(value, MAX_VALUE - 1);
}

static inline int sanitize_rel(const char *rel) {
    return sanitize_input(rel, MAX_REL - 1);
}

static inline int sanitize_href(const char *href) {
    return sanitize_input(href, MAX_HREF - 1);
}

static inline int _verify_hash(const unsigned char *stored,
                               const unsigned char *computed,
                               const char *passphrase,
                               size_t hash_len) {
    unsigned char acc = 0;
    for (size_t i = 0; i < hash_len && passphrase[i]; i++)
        acc |= stored[i] ^ computed[i];
    return acc == 0;
}

#define VERIFY_CREDENTIALS(identity_ptr, pwd_str, on_fail)               \
    do {                                                                  \
        unsigned char _vc_hash[PASSWORD_HASH_LEN];                        \
        crypto_hash_password((pwd_str), _vc_hash);                        \
        if (!_verify_hash((identity_ptr)->password_hash,                  \
                          _vc_hash, (pwd_str), PASSWORD_HASH_LEN)) {     \
            on_fail;                                                      \
        }                                                                 \
    } while (0)

#endif
