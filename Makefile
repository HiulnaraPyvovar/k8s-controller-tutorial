APP           := k8s-controller-tutorial
VERSION       ?= $(shell git describe --tags --always --dirty)
TAG           ?= latest
REPO_OWNER    ?= hiulnarapyvovar # має бути lowercase!
DOCKER_REGISTRY ?= ghcr.io
IMAGE_NAME    := $(DOCKER_REGISTRY)/$(REPO_OWNER)/$(APP)
BUILD_FLAGS   := -v -o $(APP) -ldflags "-X=github.com/$(REPO_OWNER)/$(APP)/cmd.appVersion=$(VERSION)"

.PHONY: all build test run docker-build docker-push clean

all: build

## Build Go binary
build:
	CGO_ENABLED=0 GOOS=$(GOOS) GOARCH=$(GOARCH) go build $(BUILD_FLAGS) main.go

## Run Go tests
test:
	go test ./...

## Run the app locally
run:
	go run main.go

## Build Docker image with version
docker-build:
	docker build \
		--build-arg VERSION=$(VERSION) \
		-t $(IMAGE_NAME):$(TAG) .

## Push Docker image to GHCR
docker-push:
	docker push $(IMAGE_NAME):$(TAG)

## Clean up local binary
clean:
	rm -f $(APP)
