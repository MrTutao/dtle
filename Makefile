OS := $(shell uname)
VERSION := $(shell sh -c 'git describe --always --tags')
BRANCH := $(shell sh -c 'git rev-parse --abbrev-ref HEAD')
COMMIT := $(shell sh -c 'git rev-parse --short HEAD')
DOCKER        := $(shell which docker)
DOCKER_IMAGE  := docker-registry:5000/actiontech/universe-compiler-udup:v2

PROJECT_NAME  = udup
VERSION       = 9.9.9.9

ifdef GOBIN
PATH := $(GOBIN):$(PATH)
else
PATH := $(subst :,/bin:,$(GOPATH))/bin:$(PATH)
endif

# Standard Udup build
default: build

# Windows build
windows: build-windows

# Only run the build (no dependency grabbing)
build:
	go build -o dist/udup -ldflags \
		"-X main.Version=$(VERSION) -X main.GitCommit=$(COMMIT) -X main.GitBranch=$(BRANCH)" \
		./cmd/udup/main.go

build-windows:
	GOOS=windows GOARCH=amd64 go build -o dist/udup.exe -ldflags \
		"-X main.Version=$(VERSION) -X main.GitCommit=$(COMMIT) -X main.GitBranch=$(BRANCH)" \
		./cmd/udup/main.go

TEMP_FILE = temp_parser_file
goyacc:
	go build -o dist/goyacc vendor/github.com/pingcap/tidb/parser/goyacc/main.go

prepare: goyacc
	dist/goyacc -o /dev/null -xegen $(TEMP_FILE) vendor/github.com/pingcap/tidb/parser/parser.y
	dist/goyacc -o vendor/github.com/pingcap/tidb/parser/parser.go -xe $(TEMP_FILE) vendor/github.com/pingcap/tidb/parser/parser.y 2>&1 | egrep "(shift|reduce)/reduce" | awk '{print} END {if (NR > 0) {print "Find conflict in parser.y. Please check y.output for more information."; system("rm -f $(TEMP_FILE)"); exit 1;}}'
	rm -f $(TEMP_FILE)
	rm -f y.output

ifeq ($(OS),Darwin)
		@/usr/bin/sed -i "" 's|//line.*||' vendor/github.com/pingcap/tidb/parser/parser.go
		@/usr/bin/sed -i "" 's/yyEofCode/yyEOFCode/' vendor/github.com/pingcap/tidb/parser/parser.go
else
		@sed -i -e 's|//line.*||' -e 's/yyEofCode/yyEOFCode/' vendor/github.com/pingcap/tidb/parser/parser.go
endif

	@awk 'BEGIN{print "// Code generated by goyacc"} {print $0}' vendor/github.com/pingcap/tidb/parser/parser.go > tmp_parser.go && mv tmp_parser.go vendor/github.com/pingcap/tidb/parser/parser.go;

# run package script
package:
	./scripts/build.py --package --version="$(VERSION)" --platform=linux --arch=amd64 --clean --no-get

# Run "short" unit tests
test-short: vet
	go test -short ./...

vet:
	go vet ./...

fmt:
	gofmt -s -w .

mtswatcher: helper/mtswatcher/mtswatcher.go
	go build -o dist/mtswatcher ./helper/mtswatcher/mtswatcher.go

docker_rpm:
	$(DOCKER) run -v $(shell pwd)/:/universe/src/udup --rm $(DOCKER_IMAGE) -c "cd /universe/src/udup; GOPATH=/universe make prepare package"

upload:
	curl -T $(shell pwd)/dist/*.rpm -u admin:ftpadmin ftp://release-ftpd/actiontech-${PROJECT_NAME}/qa/${VERSION}/${PROJECT_NAME}-${VERSION}-qa.x86_64.rpm
	curl -T $(shell pwd)/dist/*.rpm.md5 -u admin:ftpadmin ftp://release-ftpd/actiontech-${PROJECT_NAME}/qa/${VERSION}/${PROJECT_NAME}-${VERSION}-qa.x86_64.rpm.md5

.PHONY: test-short vet fmt build default
