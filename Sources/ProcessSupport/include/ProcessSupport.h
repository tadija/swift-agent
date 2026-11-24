#ifndef SWIFT_AGENT_PROCESS_SUPPORT_H
#define SWIFT_AGENT_PROCESS_SUPPORT_H
#include <sys/types.h>
// Returns a POSIX error number, or zero and the child PID on success.
int swift_agent_spawn(const char *executable, char *const argv[], char *const envp[],
              const char *cwd, int input_fd, int output_fd, pid_t *child);
#endif
