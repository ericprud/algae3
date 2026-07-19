# Algae 3 - parser skeleton
# `make check` parses every example and prints its action algebra.

CC      = cc
CFLAGS  = -O2 -Wall -Wno-unused-function
BISON   = bison
FLEX    = flex

GEN     = lib/Algae3Parser.tab.c lib/Algae3Parser.tab.h lib/Algae3Scanner.yy.c
BIN     = bin/algae3

all: $(BIN)

lib/Algae3Parser.tab.c lib/Algae3Parser.tab.h: lib/Algae3Parser.y
	$(BISON) -d -o lib/Algae3Parser.tab.c lib/Algae3Parser.y

lib/Algae3Scanner.yy.c: lib/Algae3Scanner.l lib/Algae3Parser.tab.h
	$(FLEX) -o $@ lib/Algae3Scanner.l

$(BIN): lib/Algae3Parser.tab.c lib/Algae3Scanner.yy.c
	mkdir -p bin
	$(CC) $(CFLAGS) -o $@ lib/Algae3Parser.tab.c lib/Algae3Scanner.yy.c

check: $(BIN)
	$(BIN) examples/*.a3

clean:
	rm -rf bin $(GEN)

.PHONY: all check clean
