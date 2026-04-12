#ifndef PROTOCOL_H
#define PROTOCOL_H

#include <sys/types.h>

#define MAIN_FIFO "tmp/main_fifo"
#define MAX_CMD_LEN 512

typedef enum {
    REQ_EXECUTE, // opção -e (Runner quer inciar um comando)
    REQ_STATUS, // opção -c (Consulta)
    REQ_STOP, // opção -s (Shutdown)
    REQ_FINISHED // Runner avisa que terminou o comando 
} RequestType;

typedef struct{
    RequestType type; 
    pid_t runner_pid; // Usado para criar o nome do pipe de repsosta
    int user_id; 
    char command[MAX_CMD_LEN];
} Message; 

#endif

