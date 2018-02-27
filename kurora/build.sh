#!/usr/bin/env bash

B=bundle

BASETAG=foldr/kurorabase:latest
CRAWLERTAG=foldr/kuroracrawler:latest

#$B install
#$B exec warble jar
docker build -t $BASETAG -f Dockerfile.base .
docker build -t $CRAWLERTAG -f Dockerfile.crawler .
