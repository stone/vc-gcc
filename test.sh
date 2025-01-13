#!/bin/bash
CONTAINER="${1:-vs-gcc-varnish-plus-vs-gcc-1}"
docker cp vcl "${CONTAINER}":/tmp/vcl
docker exec "${CONTAINER}" bash -c 'for file in /tmp/vcl/*.vcl; do \
  basename=${file##*/}; name=${basename%.vcl}; \
  echo "Loading/Compiling: $basename"; \
  echo "-------------------------------------------------------" ; \
  varnishadm vcl.load "$name" "$file"; \
  echo "-------------------------------------------------------" ; \
  sleep 1; \
  done'
