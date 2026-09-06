#include <libproc.h>
#include <mach/mach_time.h>
#include <stdio.h>
#include <stdlib.h>
#include <inttypes.h>
int main(int argc, char **argv) {
    mach_timebase_info_data_t base; mach_timebase_info(&base);
    double seconds = (double)base.numer / base.denom / 1e9;
    putchar('{');
    for (int i = 1; i < argc; i++) {
        int pid = atoi(argv[i]); struct rusage_info_v2 r;
        printf("%s\"%d\":", i == 1 ? "" : ",", pid);
        if (pid < 1 || proc_pid_rusage(pid, RUSAGE_INFO_V2, (rusage_info_t *)&r) != 0) { fputs("null", stdout); continue; }
        printf("{\"cpu\":%.9f,\"childrenCPU\":%.9f,\"footprint\":%" PRIu64 ",\"resident\":%" PRIu64 ",\"interruptWakeups\":%" PRIu64 ",\"packageWakeups\":%" PRIu64 ",\"bytesWritten\":%" PRIu64 ",\"birth\":%" PRIu64 "}",
               ((double)r.ri_user_time + r.ri_system_time) * seconds,
               ((double)r.ri_child_user_time + r.ri_child_system_time) * seconds,
               r.ri_phys_footprint, r.ri_resident_size, r.ri_interrupt_wkups, r.ri_pkg_idle_wkups, r.ri_diskio_byteswritten, r.ri_proc_start_abstime);
    }
    puts("}");
}
