#ifndef HUB_EXPORT_H
#define HUB_EXPORT_H

#include "identity.h"

int hub_export_check_access(Identity *id, const char *subject);
int hub_export_validate_path(const char *path);
size_t hub_export_estimate_size(Identity *id);
uint32_t hub_export_compute_checksum(const void *data, size_t len);
int hub_export_verify_checksum(const void *data, size_t len, uint32_t expected);
int hub_export_format_filename(uint32_t id, char *buf, size_t buf_len);
int hub_export_validate_header(const void *data, size_t len);
int hub_export_rate_check(uint32_t identity_id, int max_per_minute);

#endif
