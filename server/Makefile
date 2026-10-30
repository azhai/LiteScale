ODIN ?= odin
BIN  := bin/litescale-server
SRC  := src

.PHONY: all build run test clean

all: build

build:
	@mkdir -p bin
	$(ODIN) build $(SRC) -out:$(BIN) -o:speed
	@echo "built $(BIN)"

run: build
	./$(BIN) -addr 127.0.0.1:9429 -data ./data

test: build
	./test_e2e.sh ./$(BIN)

clean:
	rm -rf bin
