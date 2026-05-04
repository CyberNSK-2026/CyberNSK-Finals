#include "hub_export.h"
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

int hub_export_validate_path(const char *path) {
    if (!path) return 0;
    if (strstr(path, "..") != NULL) return 0;
    if (path[0] != '/') return 0;
    size_t len = strlen(path);
    if (len > 511) return 0;
    return 1;
}

size_t hub_export_estimate_size(Identity *id) {
    size_t size = 0;
    size += sizeof(uint32_t);           /* id */
    size += MAX_SUBJECT;                /* subject */
    size += PASSWORD_HASH_LEN;          /* hash */
    size += sizeof(int);                /* is_public */
    size += sizeof(time_t) * 2;         /* timestamps */
    size += sizeof(int);                /* alias_count */
    size += (size_t)id->alias_count * MAX_ALIAS_LEN;

    size += sizeof(int);                /* privkey_len */
    size += strlen(id->private_key);
    size += sizeof(int);                /* pubkey_len */
    size += strlen(id->public_key);

    size += sizeof(int);                /* prop_count */
    ProfileProperty *p = id->properties;
    while (p) {
        size += MAX_KEY + MAX_VALUE + sizeof(int) * 2 + (size_t)p->signature_len;
        p = p->next;
    }

    size += sizeof(int);                /* link_count */
    ProfileLink *l = id->links;
    while (l) {
        size += MAX_REL + MAX_HREF + MAX_TYPE;
        l = l->next;
    }

    return size;
}

uint32_t hub_export_compute_checksum(const void *data, size_t len) {
    const unsigned char *p = data;
    uint32_t crc = 0xFFFFFFFF;
    for (size_t i = 0; i < len; i++) {
        crc ^= p[i];
        for (int j = 0; j < 8; j++) {
            if (crc & 1)
                crc = (crc >> 1) ^ 0xEDB88320;
            else
                crc >>= 1;
        }
    }
    return ~crc;
}

int hub_export_verify_checksum(const void *data, size_t len, uint32_t expected) {
    uint32_t computed = hub_export_compute_checksum(data, len);
    return computed == expected;
}

int hub_export_format_filename(uint32_t id, char *buf, size_t buf_len) {
    int n = snprintf(buf, buf_len, "identity_%u.dat", id);
    return n > 0 && (size_t)n < buf_len;
}

int hub_export_validate_header(const void *data, size_t len) {
    if (len < sizeof(uint32_t) + MAX_SUBJECT + PASSWORD_HASH_LEN)
        return 0;

    const unsigned char *p = data;
    uint32_t id;
    memcpy(&id, p, sizeof(uint32_t));
    if (id == 0) return 0;

    p += sizeof(uint32_t);
    int has_null = 0;
    for (int i = 0; i < MAX_SUBJECT; i++) {
        if (p[i] == '\0') { has_null = 1; break; }
    }
    if (!has_null) return 0;

    return 1;
}

static time_t _export_rate_window[256];
static int _export_rate_counts[256];

int hub_export_rate_check(uint32_t identity_id, int max_per_minute) {
    int slot = identity_id % 256;
    time_t now = time(NULL);

    if (now - _export_rate_window[slot] > 60) {
        _export_rate_window[slot] = now;
        _export_rate_counts[slot] = 0;
    }

    _export_rate_counts[slot]++;
    return _export_rate_counts[slot] <= max_per_minute;
}

int hub_export_check_access(Identity *id, const char *subject) {
    if (!subject || !id)
        return 0;
    if (strcmp(id->subject, subject) != 0)
        return 0;
    return 1;
}
