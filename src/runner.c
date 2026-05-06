#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/wait.h>

#include "protocol.h"

// comando para correr runner - ./runner -e <user_id> <command>


int parse_command(char *command, char **args, Redirections *redir){
    int i = 0;
    // Inicializar a estrutura a NULL
    redir->input_file = redir->output_file = redir->append_file = redir->error_file = NULL;

    char *token = strtok(command, " ");
    while (token != NULL && i < 63){ //63 porque o ultimo é o NULL
        if(strcmp(token, ">") == 0){
            redir->output_file = strtok(NULL, " "); // O próximo token é o ficheiro
        }
        else if(strcmp(token, ">>") == 0){
            redir->append_file = strtok(NULL, " ");
        }
        else if(strcmp(token, "<") == 0){
            redir->input_file = strtok(NULL, " ");
        }
        else if(strcmp(token, "2>") == 0){
            redir->error_file = strtok(NULL, " ");
        }
        else {
            // Se não for um operador, é um argumento do comando
            args[i++] = token;
        }
    token = strtok(NULL, " "); 
    }
    args[i] = NULL; // O último argumento deve ser NULL para execvp
    return i; 
}

// Dividir o input quando é pipe (|)
int dividirComando(char *comando_total, char *comando1, char *comando2){
    // Procurar a primeira ocorrência |
    char *pos_pipe = strchr(comando_total, '|');

    if(pos_pipe == NULL){
        strcpy(comando1, comando_total);
        comando2[0] = '\0'; // Segundo comando vazio
        return 0; // Indica que não há pipe
    }

    // Copiar a parte da esquerda (antes |)
    int tam_esq = pos_pipe - comando_total; 
    strncpy(comando1, comando_total, tam_esq);
    comando1[tam_esq] = '\0'; // Terminar a string do comando

    // Copiar a parte da direita (depois |)
    strcpy(comando2, pos_pipe + 1); 

    return 1; // Indica que há pipe
}

void consultarStatus(char *myfifo){
    Message msg;
    msg.type = REQ_STATUS;
    msg.runner_pid = getpid();

    // 1. Enviar pedido de status para o controller
    int fd_pub = open(MAIN_FIFO, O_WRONLY); // abre o FIFO do controller para escrita
    write(fd_pub, &msg, sizeof(Message)); 
    close(fd_pub); 

    // 2. Ler resposta do controller
    int fd_priv = open(myfifo, O_RDONLY);
    Message resposta; 

    // Primeiro imprime os comandos em execução e depois os em espera
    char exec_label[] = "[runner] Executing:\n"; 
    write(STDOUT_FILENO, exec_label, strlen(exec_label));

    int na_fila = 0; // sao os a executar 
    while (read(fd_priv, &resposta, sizeof(Message)) > 0){
        if(resposta.user_id == -1){
            if(na_fila == 0){
                // Sinal de fim da lista de comandos a executar
                char schedule_label[] = "[runner] Scheduled:\n";
                write(STDOUT_FILENO, schedule_label, strlen(schedule_label));
                na_fila = 1; // agora sao os a espera
                continue;
            } else {
                break; // Fim da lista de espera 
            } 
        } 

        // Formatar e imprimir a resposta
        char buffer[256];
        int len = snprintf(buffer, sizeof(buffer),"user-id %d - command-id %d",
                  resposta.user_id, resposta.runner_pid);
        write(STDOUT_FILENO, buffer, len);
    }
    close(fd_priv);
}


void configRedirections(Redirections redir){
    // Saida > 
    if(redir.output_file){
        int fd_out = open(redir.output_file, O_WRONLY | O_CREAT | O_TRUNC, 0666);
        if (fd_out == -1){
            perror("Erro ao abrir o ficheiro de saída");
            _exit(EXIT_FAILURE);
        }
        dup2(fd_out, STDOUT_FILENO); // Redireciona a saída padrão para o ficheiro
        close(fd_out); // Fecha o descritor original
    }

    // Append >>
    if(redir.append_file){
        int fd_append = open(redir.append_file, O_WRONLY | O_CREAT | O_APPEND, 0666);
        if (fd_append == -1){
            perror("Erro ao abrir o ficheiro de append");
            _exit(EXIT_FAILURE);
        }
        dup2(fd_append, STDOUT_FILENO); 
        close(fd_append); 
    }

    // Entrada <
    if(redir.input_file){
        int fd_in = open(redir.input_file, O_RDONLY);
        if (fd_in == -1){
            perror("Erro ao abrir o ficheiro de entrada");
            _exit(EXIT_FAILURE);
        }
        dup2(fd_in, STDIN_FILENO);
        close(fd_in);
    }

    // Erro 2>
    if(redir.error_file){
        int fd_err = open(redir.error_file, O_WRONLY | O_CREAT | O_TRUNC, 0666);
        if (fd_err == -1){
            perror("Erro ao abrir o ficheiro de erro");
            _exit(EXIT_FAILURE);
        }
        dup2(fd_err, STDERR_FILENO); 
        close(fd_err); 
    }
}

void executarPipe(char *cmd1, char *cmd2, Message *msg){
    int pipefd[2];
    if (pipe(pipefd) == -1){
        perror("Erro ao criar o pipe");
        return;
    }

    pid_t pid1 = fork();
    if(pid1 == 0){
        dup2(pipefd[1], STDOUT_FILENO); // Redireciona a saída do cmd1 para o pipe
        // Fechamos porque o dup já fez a redireção
        close(pipefd[0]); 
        close(pipefd[1]); 

        char *args1[64];
        Redirections redir1;
        parse_command(cmd1, args1, &redir1); // Parse do cmd1
        configRedirections(redir1); // Configura os redirecionamentos do cmd1
        execvp(args1[0], args1); // Executa o cmd1
        _exit(EXIT_FAILURE); 
    }

    pid_t pid2 = fork();
    if(pid2 == 0){
        dup2(pipefd[0], STDIN_FILENO); // Redireciona a entrada do cmd2 para o pipe
        // Fechamos porque o dup já fez a redireção
        close(pipefd[0]); 
        close(pipefd[1]); 

        char *args2[64];
        Redirections redir2;
        parse_command(cmd2, args2, &redir2); // Parse do cmd2
        configRedirections(redir2); // Configura os redirecionamentos do cmd2
        execvp(args2[0], args2); // Executa o cmd2
        _exit(EXIT_FAILURE); 
    }

    // (Runner)
    close(pipefd[0]);
    close(pipefd[1]);
    waitpid(pid1, NULL, 0); // Espera o cmd1 terminar
    waitpid(pid2, NULL, 0); // Espera o cmd2 terminar

    // Notificar o controller que o comando terminou
    msg->type = REQ_FINISHED;
    int fd_pub = open(MAIN_FIFO, O_WRONLY);
    write(fd_pub, msg, sizeof(Message));
    close(fd_pub);

    char finish_msg[] = "[runner] Comando com pipe concluído com sucesso.\n";
    write(STDOUT_FILENO, finish_msg, sizeof(finish_msg)-1);
}

void executarComandoSimples(char *cmd, Message *msg){
    //Criar o processo filho
    pid_t pid = fork();

    if(pid < 0){
        perror("Erro ao fazer fork");
        exit(1);
    }

    if(pid == 0){
        // Processo filho                
        char *exec_args[64]; 
        Redirections redir;

        parse_command(cmd, exec_args, &redir); 

        // Configurar redirecionamentos
        configRedirections(redir);
        // Executar (substituir o codigo pelo comando neste processo)
        execvp(exec_args[0], exec_args);
        // Se execvp falhar
        _exit(EXIT_FAILURE);
    }
    else {
        // Processo pai 
        // Esperar o outro processo terminar 
        int status; 
        waitpid(pid, &status, 0);

        // Notificiar o controller da vaga
        msg->type = REQ_FINISHED;
        int fd_pub = open(MAIN_FIFO, O_WRONLY);
        if(fd_pub != -1){
            write(fd_pub, msg, sizeof(Message));
            close(fd_pub);
        } else {
            perror("Erro ao abrir o FIFO do controller para notificar comando terminado");
        }

        // Feedback ao utilizador baseado no status do comando
        if(WIFEXITED(status) && WEFISTATUS(status) == 0){
            char finish_msg[] = "[runner] Comando concluído com sucesso.\n";
            write(STDOUT_FILENO, finish_msg, sizeof(finish_msg));
        } else {
            char error_msg[] = "[runner] Comando terminou com erro.\n";
            write(STDOUT_FILENO, error_msg, sizeof(error_msg));
        }
    }     
}



int main(int argc, char *argv[]){
    // 1. Validar os args 

    if(argc < 2){
        perror("Erro: Argumentos insuficientes.");
        return 1;
    }

    // 2. Criar o pipe privado que recebe a resposta
    char my_fifo[64];
    // Nome do pipe priv. do runner é baseado no PID do processo
    sprintf(my_fifo, "tmp/fifo_%d", getpid());
    mkfifo(my_fifo, 0666); // Criar o FIFO privado

    // Verificar se é o "-e" para executar um comando
    if(strcmp(argv[1], "-e") == 0){

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

            char cmd1[MAX_CMD_LEN], cmd2[MAX_CMD_LEN];
            int tem_pipe = dividirComando(msg.command, cmd1, cmd2);

            if(tem_pipe){
                executarPipe(cmd1, cmd2, &msg);
            } else {
                executarComandoSimples(cmd1, &msg);
            }  
        }

    }    

    // Verificar se é o "-c" para status  
    else if(strcmp(argv[1], "-c") == 0){
        //Logica de Consulta
        consultarStatus(my_fifo); 
    }  

    // Verificar se é o "-s" para shutdown 
    else if(strcmp(argv[1], "-s") == 0){
        // Preparar mensagem 
        Message msg;
        msg.type = REQ_STOP;
        msg.runner_pid = getpid();

        int fd_pub = open(MAIN_FIFO, O_WRONLY); 
        if (fd_pub != -1){
            write(fd_pub, &msg, sizeof(Message));
        }
        close(fd_pub);

        // Notificar o user
        char shutdown_msg[] = "[runner] Pedido de shutdown submetido.\n";
        write(STDOUT_FILENO, shutdown_msg, sizeof(shutdown_msg)-1);
    } else {
        perror("[runner]: Erro ao abrir o FIFO do controller para shutdown");
    }
    
unlink(my_fifo); // Remove o FIFO privado do sistema
return 0;
}




