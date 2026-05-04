#ifndef HUB_AUTH_H
#define HUB_AUTH_H

#include "identity.h"

int hub_verify_credentials(const unsigned char *stored_hash,
                           const char *password);
int hub_validate_password_strength(const char *password);
int hub_check_subject_format(const char *subject);
void hub_derive_session_token(const unsigned char *hash,
                              uint32_t identity_id, char *token_out);
int hub_validate_session_token(const unsigned char *hash,
                               uint32_t identity_id, const char *token);
int hub_password_complexity_score(const char *password);
void hub_hash_to_hex(const unsigned char *hash, size_t len, char *hex_out);
int hub_hex_to_hash(const char *hex, unsigned char *hash_out, size_t max_len);
int hub_check_credential_age(const Identity *id, int max_age_days);

#endif
