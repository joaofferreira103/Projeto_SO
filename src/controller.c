#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/types.h>

#include "protocol.h"

typedef struct node{
    Message msg; // Dados do pedido
    struct node *next; // Ponteiro para o proximo pedido na fila
} CommandNode; 

// Variáveis globais para a fila de pedidos
CommandNode *primeiro_fila = NULL; // Aponta para o primeiro pedido 
CommandNode *ultimo_fila = NULL; // Aponta para o ultimo pedido


void InserirPedido(Message pedido){
    CommandNode *novo_node = malloc(sizeof(CommandNode));
    novo_node->msg = pedido;
    novo_node->next = NULL;

    if(ultimo_fila == NULL){
        primeiro_fila = novo_node;
        ultimo_fila = novo_node;
    }
    else{
        ultimo_fila->next = novo_node;
        ultimo_fila = novo_node;
    }
}

Message RetirarPedido(){
    if(primeiro_fila == NULL){
        Message empty_msg;
        return empty_msg;
    }

    CommandNode *temp = primeiro_fila;
    Message pedido_atual = temp->msg;

    primeiro_fila = primeiro_fila->next;
    if(primeiro_fila == NULL){
        ultimo_fila = NULL;
    }

    free(temp);
    return pedido_atual;
}


void GerirPedidos(int *tasks_running, int max_simultaneo){ 
    // Quando há vagas e pedidos na fila
    while(*tasks_running < max_simultaneo && primeiro_fila != NULL){

        // Retira o próximo pedido da fila
        Message prox_pedido = RetirarPedido();

        // Abre o pipe privado do runner para enviar a autorização
        char runner_fifo[64];
        snprintf(runner_fifo, sizeof(runner_fifo), "tmp/fifo_%d", prox_pedido.runner_pid);

        int fd_res = open (runner_fifo, O_WRONLY);

        // Verificar se a abertura do pipe privado foi bem-sucedida
        if (fd_res != -1){
            int autorizado = 1; // Simula autorização para o pedido
            write(fd_res, &autorizado, sizeof(int)); // Envia a autorização para o runner
            close(fd_res); // Fecha o pipe privado após enviar a resposta

            (*tasks_running)++; // Incrementa o número de tarefas em execução
        }
        // Aqui podemos guardar o tempo de início para o log 
        // Ver se fazemos isso depois 
    }
}



int main (int argc, char *argv[]){

    // Verificar os argumentos 
    if (argc < 3){
        // Erro 
        return 1;
    }

    // Maximo de tarefas simultaneas
    int max_simultaneo = atoi(argv[1]);
    int tasks_running = 0; 

    // 1. Criar o FIFO (pipe com nome)
    // O 0666 DEFINE permissoes de leitura e escrita para todos os usuários

    if(mkfifo(MAIN_FIFO, 0666) == -1){
        perror("Erro ao criar o FIFO");       
    }

    // 2. Abrir o FIFO para leitura 
    // O controller bloqueia aqui até o primeiro runner abrir para escrita

    int fd_main = open(MAIN_FIFO, O_RDONLY);
    if(fd_main == -1){
        perror("Erro ao abrir o FIFO para leitura");
        return 1;
    }   

    Message msg;
    int shutdown_flag = 0; // Flag para indicar se o controller deve encerrar
    int keep_running = 1; // Flag para controlar o loop principal do controller

    // 3. Loop para atender aos pedidos de runners 
    while(keep_running && (read(fd_main, &msg, sizeof(Message))) > 0){
        if(msg.type == REQ_EXECUTE){
            if(shutdown_flag){
                char runner_fifo[64];
                snprintf(runner_fifo, sizeof(runner_fifo), "tmp/fifo_%d", msg.runner_pid);
                
                // Abre o fifo e avisa que o sistema vai encerrar
                int fd_res = open(runner_fifo, O_WRONLY);
                if(fd_res != -1){
                    int status = STATUS_SHUTDOWN; 
                    write(fd_res, &status, sizeof(int)); 
                    close(fd_res);    
                }
                printf("Pedido do utilizador %d recusado. O sistema irá encerrar em breve.\n", msg.user_id);
            }    
            else{
            // Chegou pedido -> mete na fila
            InserirPedido(msg);
            // podemos fazer este printf para verificar que o pedido chegou ao controller ??????
            printf("O comando: %s do utilizador %d foi recebido.\n", msg.command, msg.user_id);
            GerirPedidos(&tasks_running, max_simultaneo); 
            }
        }

        else if(msg.type == REQ_FINISHED){
            // O runner avisa que terminou o comando
            tasks_running--; 
            GerirPedidos(&tasks_running, max_simultaneo); // Vaga para novas tarefas

            if(shutdown_flag && tasks_running == 0){
                keep_running = 0; // Sinaliza para sair do loop principal
            }
        }

        else if(msg.type == REQ_STATUS){
            char private_fifo[64];
            snprintf(private_fifo, sizeof(private_fifo), "tmp/fifo_%d", msg.runner_pid);
            int fd_res = open(private_fifo, O_WRONLY);

            if(fd_res != -1){
                // METER LOGICA DE CORRER A LISTA DE COMANDOS 
                // ENVIAR A INFO DOS A DECORRER E DOS NA FILA

                close(fd_res);
                
            }
        }

        else if (msg.type == REQ_STOP){
            // Marcar a flag de encerrado para nao aceitar mais pedidos
            shutdown_flag = 1;

            // Não havendo ninguem a correr, fecha
            if(tasks_running == 0){
                keep_running = 0; // Sinaliza para sair do loop principal
                // VER COMO FAZER O CICLO PARAR APOS OS REQUESTS TERMINAREM E O SHUTDOWN_FLAG ESTAR ATIVO
            }
        }
    // 4. Fechar o FIFO e remover o arquivo do sistema
    close(fd_main);
    unlink(MAIN_FIFO); // Remove o ficheiro do pipe do sistema 

    }
    return 0; 
}
