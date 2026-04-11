#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/types.h>

#include "protocol.h"

int main (int argc, char *argv[]){
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
    int bytesRead;

    // 3. Loop para atender aos pedidos de runners 
    while((bytesRead = read(fd_main, &msg, sizeof(Message))) > 0){
        if(msg.type == REQ_EXECUTE){
            // Por enquanto confirma que recebeu
            printf("O comando: %s do utilizador %d foi recebido.\n", msg.command, msg.user_id);
        }
        else if(msg.type == REQ_STOP){
            printf("A desligar o controller...\n");
            break; // Sai do loop para encerrar o controller
        }
    }

    // 4. Fechar o FIFO e remover o arquivo do sistema
    close(fd_main);
    unlink(MAIN_FIFO); // Remove o ficheiro do pipe do sistema 

    return 0; 
}

