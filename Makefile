CC = gcc
CFLAGS = -Wall -g -Iinclude
LDFLAGS =

HEADERS = include/utils.h include/protocol.h
CONTROLLER_DEPS = obj/controller.o obj/utils.o
RUNNER_DEPS = obj/runner.o

all: folders controller runner

controller: bin/controller

runner: bin/runner

folders:
	@mkdir -p src include obj bin tmp logs

bin/controller: $(CONTROLLER_DEPS) $(HEADERS)
	$(CC) $(LDFLAGS) $(CONTROLLER_DEPS) -o $@

bin/runner: $(RUNNER_DEPS) $(HEADERS)
	$(CC) $(LDFLAGS) $(RUNNER_DEPS) -o $@

obj/%.o: src/%.c $(HEADERS)
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	rm -f obj/* tmp/* bin/*

.PHONY: all controller runner folders clean
