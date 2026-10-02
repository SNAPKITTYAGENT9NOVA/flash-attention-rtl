# C stack: layered, deterministic core. Targets: all, test, san, demo, clean.
CC      ?= gcc
CFLAGS  ?= -std=c11 -O2 -g
WARN    := -Wall -Wextra -Wpedantic -Wshadow -Wconversion -Werror
INC     := -Iinclude
DEFS    := -D_GNU_SOURCE

SRC     := $(wildcard src/*.c)
OBJ     := $(patsubst src/%.c,build/%.o,$(SRC))
TESTS   := $(patsubst tests/%.c,build/%,$(wildcard tests/test_*.c))

all: build/libcstack.a build/cstack_demo $(TESTS)

build/%.o: src/%.c $(wildcard include/*.h)
	@mkdir -p build
	$(CC) $(CFLAGS) $(WARN) $(DEFS) $(INC) -c $< -o $@

build/libcstack.a: $(OBJ)
	ar rcs $@ $^

build/test_%: tests/test_%.c build/libcstack.a tests/cs_test.h
	$(CC) $(CFLAGS) $(WARN) $(DEFS) $(INC) $< build/libcstack.a -o $@

build/cstack_demo: demo/cstack_demo.c build/libcstack.a
	$(CC) $(CFLAGS) $(WARN) $(DEFS) $(INC) $< build/libcstack.a -o $@

test: all
	@set -e; for t in $(TESTS); do ./$$t; done

# same tests under AddressSanitizer + UndefinedBehaviorSanitizer
san:
	$(MAKE) clean
	$(MAKE) test CFLAGS="-std=c11 -O1 -g -fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer"

demo: build/cstack_demo
	./build/cstack_demo

clean:
	rm -rf build

.PHONY: all test san demo clean
