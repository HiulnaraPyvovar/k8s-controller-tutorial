APP = k8s-controller
VERSION ?= $(shell git describe --tags --abbrev=0)
COMMIT  ?= $(shell git rev-parse --short HEAD)
DATE    ?= $(shell date -u +'%Y-%m-%dT%H:%M:%SZ')
GHCR_REGISTRY := ghcr.io/hiulnarapyvovar
ENVTEST_VERSION := 1.30.0
SETUP_ENVTEST := $(shell go env GOPATH)/bin/setup-envtest

LD_FLAGS = -X=github.com/silhouetteUA/$(APP)/cmd.Version=$(VERSION) \
           -X=github.com/silhouetteUA/$(APP)/cmd.Commit=$(COMMIT) \
           -X=github.com/silhouetteUA/$(APP)/cmd.BuildDate=$(DATE)

BUILD_FLAGS = -v -o bin/$(APP) -ldflags "$(LD_FLAGS)"

.PHONY: all build test run docker-build clean envtest format

all: build

envtest:
	@echo "Installing setup-envtest..."
	go install sigs.k8s.io/controller-runtime/tools/setup-envtest@latest
	@echo "Downloading envtest binaries for version $(ENVTEST_VERSION)..."
	@$(SETUP_ENVTEST) use $(ENVTEST_VERSION) -p path

test: envtest
	@echo "Retrieving KUBEBUILDER_ASSETS path..."
	@export KUBEBUILDER_ASSETS="$$( $(SETUP_ENVTEST) use $(ENVTEST_VERSION) -p path )"; \
	echo "KUBEBUILDER_ASSETS=$$KUBEBUILDER_ASSETS"; \
	KUBEBUILDER_ASSETS=$$KUBEBUILDER_ASSETS go test ./...

format:
	gofmt -s -w ./

build:
	CGO_ENABLED=0 GOOS=$(GOOS) GOARCH=$(GOARCH) go build $(BUILD_FLAGS) main.go

run:
	go run main.go

docker-build:
	docker build --build-arg VERSION=$(VERSION) \
	             --build-arg COMMIT=$(COMMIT) \
	             --build-arg DATE=$(DATE) \
	             -t $(GHCR_REGISTRY)/$(APP):$(VERSION)-$(COMMIT) .

clean:
	rm -rf bin
	go clean -cache
