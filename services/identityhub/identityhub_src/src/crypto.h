#ifndef CRYPTO_H
#define CRYPTO_H

#include "identity.h"

int crypto_generate_rsa_keypair(Identity *id);
int crypto_sign_property(Identity *id, ProfileProperty *prop);
int crypto_verify_property(Identity *id, ProfileProperty *prop);
void crypto_hash_password(const char *password, unsigned char *hash_out);

#endif
