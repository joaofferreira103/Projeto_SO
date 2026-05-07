#ifndef CONTROLLER_H 
#define CONTROLLER_H

#include <time.h>

#include "protocol.h"
#include "utils.h"

typedef struct node CommandNode;

void InserirPedido(Message pedido);

CommandNode* RetirarPedido();

void InserirAtivos (CommandNode *no);

CommandNode* RetirarAtivos(int pid);

void GerirPedidos(int *tasks_running, int max_simultaneo);

void responderStatus(Message msg_pedido);

#endif