#ifndef UTILS_H
#define UTILS_H

#include <time.h>
#include "protocol.h"

long calcularTempo(struct timespec inicio, struct timespec fim);

void registarLogs(Message msg, long espera, long resposta);

#endif