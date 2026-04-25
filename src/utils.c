#include <fcntl.h>
#include <unistd.h>
#include <string.h>
#include <stdio.h>
#include <time.h>

#include "protocol.h"

long calcularTempo(struct timespec inicio, struct timespec fim){
   long ms = (fim.tv_sec - inicio.tv_sec) * 1000; // Converte segundos para milissegundos

   // Ajusta com a diferença de nanosegundos 
   ms += (fim.tv_nsec - inicio.tv_nsec) / 1000000; // Converte nanosegundos para milissegundos

   return ms;
}

void registarLogs(Message msg, long espera, long resposta){
    char buffer[512];

    int len = snprintf(buffer, sizeof(buffer),
              "User ID: %d | Command_ID: %d | Command: %s | Tempo de espera: %ldms | Tempo de execução: %ldms | Tempo Total: %ldms\n",
               msg.user_id, msg.runner_pid, msg.command, espera, resposta, (espera + resposta));

    // Escreve o log no ficheiro
    int fd = open("logs/log.txt", O_WRONLY | O_CREAT | O_APPEND, 0666);

    if(fd == -1){
        perror("Erro ao abrir o ficheiro de logs");
        return;
    }

    if(write(fd, buffer, len) == -1){
        perror("Erro ao escrever no ficheiro de logs");
    }
    close(fd);
}

