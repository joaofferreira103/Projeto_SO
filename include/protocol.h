#ifndef PROTOCOL_H
#define PROTOCOL_H

#include <sys/types.h>

#define MAIN_FIFO "tmp/main_fifo"
#define MAX_CMD_LEN 512

typedef enum {
    REQ_EXECUTE, // opção -e
    REQ_STATUS, // opção -c
    REQ_STOP // opção -s
} RequestType;

typedef struct{
    RequestType type; 
    pid_t runner_pid; // Usado para criar o nome do pipe de repsosta
    int user_id; 
    char command[MAX_CMD_LEN];
} Message; 

#endif

