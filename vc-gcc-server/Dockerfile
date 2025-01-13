FROM golang:alpine AS builder
ARG VERSION=dev
ARG GIT_COMMIT=aabbccdd
RUN apk add --no-cache git make
WORKDIR /app
COPY . .
RUN ls -al /app
RUN go mod download
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags "-X main.Version=${VERSION} -X main.GitCommit=${GIT_COMMIT}" -a -o vs-gcc-server .

FROM quay.io/varnish-software/varnish-plus:latest
USER root
COPY --from=builder /app/vs-gcc-server /usr/bin/vs-gcc-server
USER nobody
ENTRYPOINT ["/usr/bin/vs-gcc-server"]
EXPOSE 8080
