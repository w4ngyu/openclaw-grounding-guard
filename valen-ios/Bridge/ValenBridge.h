#ifndef VALEN_BRIDGE_H
#define VALEN_BRIDGE_H
#include <stdbool.h>
#ifdef __cplusplus
extern "C" {
#endif

int valen_start_server(const char * model_path, const char * vision_path, bool gpu);
void valen_terminate_server(void);
int valen_server_is_running(void);
int valen_server_last_exit_code(void);

#ifdef __cplusplus
}
#endif
#endif
