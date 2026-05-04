.PHONY: tidy migrate build run vet test
tidy:
	go mod tidy

migrate:
	go run ./cmd/server/migrate

build:
	go build -o bin/server ./cmd/server

run:
	go run ./cmd/server

vet:
	go vet ./...

test:
	go test -race ./...
