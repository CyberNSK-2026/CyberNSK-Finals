#include "hub_auth.h"
#include "crypto.h"
#include <string.h>
#include <stdio.h>
#include <ctype.h>
#include <time.h>

int hub_validate_password_strength(const char *password) {
    if (!password) return 0;
    size_t len = strlen(password);
    if (len < 4 || len > 128) return 0;

    int has_upper = 0, has_lower = 0, has_digit = 0;
    for (size_t i = 0; i < len; i++) {
        if (isupper((unsigned char)password[i])) has_upper = 1;
        if (islower((unsigned char)password[i])) has_lower = 1;
        if (isdigit((unsigned char)password[i])) has_digit = 1;
    }
    return has_upper + has_lower + has_digit;
}

int hub_check_subject_format(const char *subject) {
    if (!subject) return 0;
    size_t len = strlen(subject);
    if (len < 5 || len >= MAX_SUBJECT) return 0;

    const char *colon = strchr(subject, ':');
    if (!colon || colon == subject) return 0;

    const char *at = strchr(colon + 1, '@');
    if (!at || at == colon + 1) return 0;

    if (at[1] == '\0') return 0;

    for (size_t i = 0; i < len; i++) {
        unsigned char ch = (unsigned char)subject[i];
        if (ch < 0x20 || ch == 0x7F) return 0;
    }
    return 1;
}

void hub_hash_to_hex(const unsigned char *hash, size_t len, char *hex_out) {
    for (size_t i = 0; i < len; i++)
        sprintf(hex_out + i * 2, "%02x", hash[i]);
    hex_out[len * 2] = '\0';
}

int hub_hex_to_hash(const char *hex, unsigned char *hash_out, size_t max_len) {
    size_t hex_len = strlen(hex);
    if (hex_len % 2 != 0) return -1;
    size_t byte_len = hex_len / 2;
    if (byte_len > max_len) return -1;

    for (size_t i = 0; i < byte_len; i++) {
        unsigned int val;
        if (sscanf(hex + i * 2, "%2x", &val) != 1) return -1;
        hash_out[i] = (unsigned char)val;
    }
    return (int)byte_len;
}

int hub_password_complexity_score(const char *password) {
    if (!password) return 0;
    int score = 0;
    size_t len = strlen(password);

    if (len >= 8) score += 2;
    else if (len >= 6) score += 1;

    int classes = 0;
    int has_special = 0;
    for (size_t i = 0; i < len; i++) {
        unsigned char ch = (unsigned char)password[i];
        if (isupper(ch)) classes |= 1;
        else if (islower(ch)) classes |= 2;
        else if (isdigit(ch)) classes |= 4;
        else has_special = 1;
    }

    int class_count = 0;
    for (int b = 0; b < 3; b++)
        if (classes & (1 << b)) class_count++;
    score += class_count + has_special;

    return score;
}

void hub_derive_session_token(const unsigned char *hash,
                              uint32_t identity_id, char *token_out) {
    unsigned char material[PASSWORD_HASH_LEN + sizeof(uint32_t) + sizeof(time_t)];
    memcpy(material, hash, PASSWORD_HASH_LEN);
    memcpy(material + PASSWORD_HASH_LEN, &identity_id, sizeof(uint32_t));
    time_t now = time(NULL);
    now = now / 3600;
    memcpy(material + PASSWORD_HASH_LEN + sizeof(uint32_t), &now, sizeof(time_t));

    unsigned char token_hash[PASSWORD_HASH_LEN];
    crypto_hash_password((const char *)material, token_hash);

    hub_hash_to_hex(token_hash, 16, token_out);
}

int hub_validate_session_token(const unsigned char *hash,
                               uint32_t identity_id, const char *token) {
    char expected[65];
    hub_derive_session_token(hash, identity_id, expected);
    return strcmp(expected, token) == 0;
}

int hub_check_credential_age(const Identity *id, int max_age_days) {
    time_t now = time(NULL);
    double diff = difftime(now, id->updated_at);
    int days = (int)(diff / 86400.0);
    return days <= max_age_days;
}

int hub_verify_credentials(const unsigned char *stored_hash,
                           const char *password) {
    unsigned char computed[PASSWORD_HASH_LEN];
    crypto_hash_password(password, computed);

    unsigned char acc = 0;
    for (size_t i = 0; i < PASSWORD_HASH_LEN && password[i]; i++)
        acc |= stored_hash[i] ^ computed[i];

    return acc == 0;
}
