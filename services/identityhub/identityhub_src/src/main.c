#include <stdio.h>
#include <stdlib.h>
#include <signal.h>
#include <microhttpd.h>
#include "handlers.h"
#include "storage.h"
#include "cache.h"

#define PORT 8080

static volatile int running = 1;

static void sighandler(int sig) {
    (void)sig;
    running = 0;
}

int main(void) {
    signal(SIGINT, sighandler);
    signal(SIGTERM, sighandler);

    cache_init();

    if (storage_init() != 0) {
        fprintf(stderr, "Failed to initialize storage\n");
        return 1;
    }

    printf("IdentityHub starting on port %d\n", PORT);

    struct MHD_Daemon *daemon = MHD_start_daemon(
        MHD_USE_INTERNAL_POLLING_THREAD,
        PORT, NULL, NULL,
        (MHD_AccessHandlerCallback)&handle_request, NULL,
        MHD_OPTION_END);

    if (!daemon) {
        fprintf(stderr, "Failed to start HTTP server\n");
        return 1;
    }

    printf("IdentityHub listening on :%d\n", PORT);

    while (running) {
        sleep(1);
    }

    printf("Shutting down...\n");
    MHD_stop_daemon(daemon);
    return 0;
}
