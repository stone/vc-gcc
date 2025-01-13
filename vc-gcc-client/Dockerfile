FROM golang:alpine AS builder
ARG VERSION=dev
ARG GIT_COMMIT=aabbccdd
RUN apk add --no-cache git make
WORKDIR /app
COPY . .
RUN ls
RUN go mod download
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags "-X main.Version=${VERSION} -X main.GitCommit=${GIT_COMMIT}" -a -o vs-gcc-client .

FROM quay.io/varnish-software/varnish-plus:latest
USER root
RUN rm -fr /usr/bin/*gcc* /usr/bin/*g++* /usr/bin/*cpp* /usr/bin/*c++* /usr/bin/*cc*
COPY --from=builder /app/vs-gcc-client /usr/bin/vs-gcc-client
# Hack because of https://varnish-cache.org/docs/trunk/reference/varnish-cli.html#quoting-pitfalls
# and how docker env is handled
RUN sed -i '${/\${EXTRA}/{s/$/ -p cc_command="vs-gcc-client %s %o"/}}' /entrypoint.sh
USER varnish
