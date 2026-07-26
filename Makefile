# Makefile for clmac.
#
# clmac itself is plain bash and needs no build step — this only builds
# the optional Go-based `clmac explore` disk analyzer (cmd/explore).
# Without it, `clmac explore` falls back to a bash implementation
# automatically; `make build` is an enhancement, not a requirement.

.PHONY: build test vet clean

BIN_DIR := bin
GO ?= go

build:
	$(GO) build -ldflags="-s -w" -o $(BIN_DIR)/clmac-explore ./cmd/explore

test:
	$(GO) test ./...

vet:
	$(GO) vet ./...

clean:
	rm -rf $(BIN_DIR)
