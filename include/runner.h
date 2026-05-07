#ifndef RUNNER_H
#define RUNNER_H

#include "protocol.h"
#include "utils.h"

int parse_command(char *command, char **args, Redirections *redir);

int dividirComando(char *comando_total, char *comando1, char *comando2);

void consultarStatus(char *myfifo);

void configRedirections(Redirections redir);

void executarPipe(char *cmd1, char *cmd2, Message *msg);

void executarComandoSimples(char *cmd, Message *msg);

#endif
