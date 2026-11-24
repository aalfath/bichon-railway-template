/*
 * freefloor.so - LD_PRELOAD shim for Bichon on small Railway volumes.
 *
 * Bichon 2.4.x refuses to run when its blob volume has less than 1 GiB free
 * (MIN_FREE_BYTES in crates/core/src/store/blob.rs): it requests a graceful
 * shutdown a few seconds after start and exits 0. Railway's Free and Trial
 * plans give a 0.5 GB volume, so upstream can never start there.
 *
 * This shim wraps statvfs() for paths under BICHON_ROOT_DIR only and scales
 * that floor to 10% of the volume size (at least 64 MiB, never above
 * upstream's 1 GiB). Volumes of 10 GiB or more are left untouched.
 *
 * It also turns off transparent huge pages for the process (Railway hosts run
 * THP "always", which inflates resident memory); set BICHON_DISABLE_THP=0 to
 * keep them.
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdlib.h>
#include <string.h>
#include <sys/prctl.h>
#include <sys/statvfs.h>

static int (*real_statvfs)(const char *, struct statvfs *);
static char prefix[4096];
static size_t plen;

__attribute__((constructor)) static void freefloor_init(void) {
    real_statvfs = (int (*)(const char *, struct statvfs *))dlsym(RTLD_NEXT, "statvfs");
    const char *root = getenv("BICHON_ROOT_DIR");
    if (root && *root && strlen(root) < sizeof(prefix)) {
        strcpy(prefix, root);
        plen = strlen(prefix);
        while (plen > 1 && prefix[plen - 1] == '/') prefix[--plen] = 0;
    }
    const char *thp = getenv("BICHON_DISABLE_THP");
    if (!thp || strcmp(thp, "0") != 0) prctl(PR_SET_THP_DISABLE, 1, 0, 0, 0);
}

int statvfs(const char *path, struct statvfs *buf) {
    if (!real_statvfs)
        real_statvfs = (int (*)(const char *, struct statvfs *))dlsym(RTLD_NEXT, "statvfs");
    int r = real_statvfs(path, buf);
    if (r != 0 || plen == 0 || strncmp(path, prefix, plen) != 0 ||
        (path[plen] != '/' && path[plen] != 0))
        return r;
    unsigned long long fr = buf->f_frsize ? buf->f_frsize : buf->f_bsize;
    if (fr == 0) return r;
    const unsigned long long gib = 1ULL << 30, min_floor = 64ULL << 20;
    unsigned long long total = (unsigned long long)buf->f_blocks * fr;
    unsigned long long floor = total / 10;
    if (floor < min_floor) floor = min_floor;
    if (floor >= gib) return r;
    unsigned long long add = (gib - floor) / fr;
    buf->f_bavail += add;
    buf->f_bfree += add;
    return r;
}
