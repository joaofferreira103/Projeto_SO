#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>

#include "protocol.h"

int main(int argc, char *argv[]){
    // 1. Validar os args 
    // para já apenas feito para o -e

    if(argc <4 && strcmp(argv[1], "-e") == 0){
        return 1;
    }

    // 2. Criar o pipe privado que recebe a resposta
    char my_fifo[64];
    // Nome do pipe priv. do runner é baseado no PID do processo
    sprintf(my_fifo, "tmp/fifo_%d", getpid());
    mkfifo(my_fifo, 0666); // Criar o FIFO privado

    // 3. Preparar a mensagem a enviar ao controller
    Message msg;
    msg.type = REQ_EXECUTE;
    msg.user_id = atoi(argv[2]);
    msg.runner_pid = getpid();

    // Copia o comando do argv[3] em diante para o ser o comando da msg
    strncpy(msg.command, argv[3], MAX_CMD_LEN - 1);

    // 4. Enviar a mensagem para o controller
    int fd_pub = open(MAIN_FIFO, O_WRONLY); // abre o FIFO do controller para escrita
    write(fd_pub, &msg, sizeof(Message)); // Envia a mensagem
    close(fd_pub); // Fecha o FIFO do controller
    
    // 5. Notificar o utilizador que o comando foi enviado

    // estou a escrever o content num array char com o sprintf 
    // e depois uso o write para escrever esse array no STDOUT verificar com stor se posso
    char submit_msg[128];
    sprintf(submit_msg, "[runner] command %d submetido\n", getpid());
    write(STDOUT_FILENO, submit_msg, strlen(submit_msg));
    
    // 6. Abre o pipe para ler a resposta do controller 
    int fd_priv = open(my_fifo, O_RDONLY); 
    int status_resposta;
    read(fd_priv, &status_resposta, sizeof(int)); // Lê a resposta do controller

    // 7. Verifica a decisão do controller 
    if (status_resposta == STATUS_SHUTDOWN){
        char msg_erro[] = "[runner] ERRO: O sistema está a encerrar. Pedido rejeitado.\n";
        write(STDOUT_FILENO, msg_erro, sizeof(msg_erro)-1);
        
        close(fd_priv); 
        unlink(my_fifo);
        exit(0); // Encerra o runner
    }

    else if (status_resposta == STATUS_OK){
        char msg_ok[] = "[runner] Pedido autorizado. A executar comando...\n";
        write(STDOUT_FILENO, msg_ok, sizeof(msg_ok)-1);

        // Aqui é onde o runner vai fazer o fork() e execvp() depois
    }

    close(fd_priv); // Fecha o FIFO privado
    unlink(my_fifo); // Remove o FIFO privado do sistema
    return 0;
}


