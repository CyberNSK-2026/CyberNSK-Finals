#include "crypto.h"
#include <openssl/rsa.h>
#include <openssl/pem.h>
#include <openssl/sha.h>
#include <openssl/evp.h>
#include <openssl/bio.h>
#include <openssl/err.h>
#include <string.h>
#include <stdio.h>

void crypto_hash_password(const char *password, unsigned char *hash_out) {
    SHA256((const unsigned char *)password, strlen(password), hash_out);
}

int crypto_generate_rsa_keypair(Identity *id) {
    EVP_PKEY *pkey = NULL;
    EVP_PKEY_CTX *ctx = EVP_PKEY_CTX_new_id(EVP_PKEY_RSA, NULL);
    if (!ctx) return -1;

    if (EVP_PKEY_keygen_init(ctx) <= 0 ||
        EVP_PKEY_CTX_set_rsa_keygen_bits(ctx, 2048) <= 0 ||
        EVP_PKEY_keygen(ctx, &pkey) <= 0) {
        EVP_PKEY_CTX_free(ctx);
        return -1;
    }
    EVP_PKEY_CTX_free(ctx);

    
    BIO *bio = BIO_new(BIO_s_mem());
    PEM_write_bio_PrivateKey(bio, pkey, NULL, NULL, 0, NULL, NULL);
    int priv_len = BIO_read(bio, id->private_key, MAX_PEM_KEY - 1);
    id->private_key[priv_len] = '\0';
    BIO_free(bio);

    
    bio = BIO_new(BIO_s_mem());
    PEM_write_bio_PUBKEY(bio, pkey);
    int pub_len = BIO_read(bio, id->public_key, MAX_PEM_KEY - 1);
    id->public_key[pub_len] = '\0';
    BIO_free(bio);

    EVP_PKEY_free(pkey);
    return 0;
}

int crypto_sign_property(Identity *id, ProfileProperty *prop) {
    if (id->private_key[0] == '\0') return -1;

    
    char data[MAX_KEY + MAX_VALUE + 2];
    snprintf(data, sizeof(data), "%s=%s", prop->key, prop->value);

    BIO *bio = BIO_new_mem_buf(id->private_key, -1);
    EVP_PKEY *pkey = PEM_read_bio_PrivateKey(bio, NULL, NULL, NULL);
    BIO_free(bio);
    if (!pkey) return -1;

    EVP_MD_CTX *md_ctx = EVP_MD_CTX_new();
    size_t sig_len = MAX_SIGNATURE;

    if (EVP_DigestSignInit(md_ctx, NULL, EVP_sha256(), NULL, pkey) <= 0 ||
        EVP_DigestSignUpdate(md_ctx, data, strlen(data)) <= 0 ||
        EVP_DigestSignFinal(md_ctx, prop->signature, &sig_len) <= 0) {
        EVP_MD_CTX_free(md_ctx);
        EVP_PKEY_free(pkey);
        return -1;
    }

    prop->signature_len = (int)sig_len;
    prop->is_signed = 1;
    EVP_MD_CTX_free(md_ctx);
    EVP_PKEY_free(pkey);
    return 0;
}

int crypto_verify_property(Identity *id, ProfileProperty *prop) {
    if (id->public_key[0] == '\0' || !prop->is_signed) return -1;

    char data[MAX_KEY + MAX_VALUE + 2];
    snprintf(data, sizeof(data), "%s=%s", prop->key, prop->value);

    BIO *bio = BIO_new_mem_buf(id->public_key, -1);
    EVP_PKEY *pkey = PEM_read_bio_PUBKEY(bio, NULL, NULL, NULL);
    BIO_free(bio);
    if (!pkey) return -1;

    EVP_MD_CTX *md_ctx = EVP_MD_CTX_new();
    int result = 0;

    if (EVP_DigestVerifyInit(md_ctx, NULL, EVP_sha256(), NULL, pkey) <= 0 ||
        EVP_DigestVerifyUpdate(md_ctx, data, strlen(data)) <= 0) {
        result = -1;
    } else {
        result = EVP_DigestVerifyFinal(md_ctx, prop->signature, prop->signature_len) == 1 ? 0 : -1;
    }

    EVP_MD_CTX_free(md_ctx);
    EVP_PKEY_free(pkey);
    return result;
}
