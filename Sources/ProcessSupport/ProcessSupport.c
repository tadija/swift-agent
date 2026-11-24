#define _GNU_SOURCE
#include "ProcessSupport.h"
#include <spawn.h>
#include <unistd.h>

int swift_agent_spawn(const char *executable, char *const argv[], char *const envp[],
              const char *cwd, int input_fd, int output_fd, pid_t *child) {
    posix_spawn_file_actions_t actions;
    posix_spawnattr_t attributes;
    int error = posix_spawn_file_actions_init(&actions);
    if (error) return error;
    error = posix_spawnattr_init(&attributes);
    if (error) { posix_spawn_file_actions_destroy(&actions); return error; }
    if (!(error = posix_spawn_file_actions_adddup2(&actions, input_fd, STDIN_FILENO)) &&
        !(error = posix_spawn_file_actions_adddup2(&actions, output_fd, STDOUT_FILENO)) &&
        !(error = posix_spawn_file_actions_adddup2(&actions, output_fd, STDERR_FILENO)) &&
        !(error = posix_spawn_file_actions_addchdir_np(&actions, cwd)) &&
        !(error = posix_spawnattr_setflags(&attributes, POSIX_SPAWN_SETPGROUP)) &&
        !(error = posix_spawnattr_setpgroup(&attributes, 0))) {
        error = posix_spawn(child, executable, &actions, &attributes, argv, envp);
    }
    posix_spawnattr_destroy(&attributes);
    posix_spawn_file_actions_destroy(&actions);
    return error;
}
