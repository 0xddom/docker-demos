FROM ubuntu:latest

RUN apt-get update
RUN apt-get install -y build-essential ruby-dev zlib1g-dev

RUN gem install fourchan-kit

ENTRYPOINT ["fourchan"]
