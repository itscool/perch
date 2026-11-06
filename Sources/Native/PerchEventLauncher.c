// A startup-only pipe opener and identity writer. execve replaces this process
// with Apple's collector: no shell, monitoring loop, extra child, or Endpoint
// Security client.
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
#define PERCH_EVENT_PIPE PERCH_IDENTITY_DIRECTORY "/events.pipe"
// The launcher, not launchd, opens the event pipe. launchd creates a missing
// StandardOutPath as an ordinary file, and eslogger then appended every event on
// the Mac to disk (EVENT-COLLECTOR.md, "The events.pipe incident"). Without
// O_CREAT nothing is ever created; a wrong path is refused and eslogger never
// starts. The blocking write-only open is the one launchd made for
// StandardOutPath: it waits here until Perch's reader attaches.
static const char *open_event_pipe(int *descriptor) {
    int fd;
    do fd = open(PERCH_EVENT_PIPE, O_WRONLY | O_NOFOLLOW | O_NOCTTY); while (fd < 0 && errno == EINTR);
    if (fd < 0) return errno == ENOENT ? "is missing" : errno == ELOOP ? "is a symbolic link" : "cannot be opened";
    struct stat st;
    const char *problem = fstat(fd, &st) ? "cannot be inspected" : !S_ISFIFO(st.st_mode) ? "is not a named pipe" :
        (st.st_mode & 07777) != 0600 ? "is not mode 0600" : st.st_uid == 0 ? "is owned by root" :
        st.st_nlink != 1 ? "has more than one link" : NULL;
    if (problem) { close(fd); return problem; }
    *descriptor = fd;
    return NULL;
}
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
    int events = -1;
    const char *problem = open_event_pipe(&events);
    if (problem) { fprintf(stderr, "Perch collector refused: %s %s.\n", PERCH_EVENT_PIPE, problem); return 78; }
    // eslogger inherits the pipe as stdout; it must survive exec.
    if (events != STDOUT_FILENO && (dup2(events, STDOUT_FILENO) != STDOUT_FILENO || close(events))) {
        fputs("Perch collector could not attach its event pipe.\n", stderr);
        return 78;
    }
    // CPU accounting must not stop event collection if a diagnostic write fails.
    if (record_identity()) fputs("Perch collector identity unavailable.\n", stderr);
    char *const arguments[] = {PERCH_COLLECTOR_EXECUTABLE, "fork", "exec", "exit", NULL};
    char *const environment[] = {"PATH=/usr/bin:/bin:/usr/sbin:/sbin", "LC_ALL=C", NULL};
    execve(PERCH_COLLECTOR_EXECUTABLE, arguments, environment);
    // A failed exec leaves a record whose process birth/liveness check will fail.
    fputs("Perch collector could not start.\n", stderr);
    return 71;
}
