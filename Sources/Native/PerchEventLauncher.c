// A startup-only identity writer. execve replaces this process with Apple's
// collector: no shell, monitoring loop, extra child, or Endpoint Security client.
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/sysctl.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <errno.h>
#include <uuid/uuid.h>
#ifndef PERCH_IDENTITY_DIRECTORY
#define PERCH_IDENTITY_DIRECTORY "/Library/Application Support/Perch Events"
#endif
#ifndef PERCH_COLLECTOR_EXECUTABLE
#define PERCH_COLLECTOR_EXECUTABLE "/usr/bin/eslogger"
#endif
#ifndef PERCH_LAUNCHER_OWNER_UID
#define PERCH_LAUNCHER_OWNER_UID 0
#endif
static int record_identity(void) {
    int directory = open(PERCH_IDENTITY_DIRECTORY, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    if (directory < 0) return -1;
    struct stat st;
    if (fstat(directory, &st) || st.st_uid != PERCH_LAUNCHER_OWNER_UID || (st.st_mode & 022)) { close(directory); return -1; }
    struct kinfo_proc info = {0}; size_t size = sizeof(info);
    int mib[] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()};
    char boot[64] = {0}; size_t boot_size = sizeof(boot); uuid_t parsed;
    if (sysctl(mib, 4, &info, &size, NULL, 0) || size != sizeof(info) ||
        info.kp_proc.p_starttime.tv_sec <= 0 ||
        sysctlbyname("kern.bootsessionuuid", boot, &boot_size, NULL, 0) ||
        boot_size > sizeof(boot) || boot[sizeof(boot)-1] != 0 || uuid_parse(boot, parsed)) { close(directory); return -1; }
    uint64_t birth = (uint64_t)info.kp_proc.p_starttime.tv_sec * 1000000 + (uint64_t)info.kp_proc.p_starttime.tv_usec;
    char record[256], temporary[80];
    int length = snprintf(record, sizeof(record), "{\"schema\":1,\"pid\":%d,\"birth\":%llu,\"boot\":\"%s\"}\n", getpid(), (unsigned long long)birth, boot);
    snprintf(temporary, sizeof(temporary), ".identity-%d-%u", getpid(), arc4random());
    int fd = openat(directory, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600);
    if (fd < 0) { close(directory); return -1; }
    int result = -1;
    if (length > 0 && (size_t)length < sizeof(record)) {
        ssize_t offset = 0;
        while (offset < length) {
            ssize_t n = write(fd, record + offset, (size_t)(length - offset));
            if (n < 0 && errno == EINTR) continue;
            if (n <= 0) break;
            offset += n;
        }
        if (offset == length && !fchmod(fd, 0644) && !fsync(fd) && !renameat(directory, temporary, directory, "collector.json")) result = 0;
    }
    close(fd); unlinkat(directory, temporary, 0); close(directory);
    return result;
}
int main(int argc, char **argv) {
    (void)argv;
    if (argc != 1 || getuid() != PERCH_LAUNCHER_OWNER_UID || geteuid() != PERCH_LAUNCHER_OWNER_UID) return 64;
    // CPU accounting must not stop event collection if a diagnostic write fails.
    if (record_identity()) fputs("Perch collector identity unavailable.\n", stderr);
    char *const arguments[] = {PERCH_COLLECTOR_EXECUTABLE, "fork", "exec", "exit", NULL};
    char *const environment[] = {"PATH=/usr/bin:/bin:/usr/sbin:/sbin", "LC_ALL=C", NULL};
    execve(PERCH_COLLECTOR_EXECUTABLE, arguments, environment);
    // A failed exec leaves a record whose process birth/liveness check will fail.
    fputs("Perch collector could not start.\n", stderr);
    return 71;
}
