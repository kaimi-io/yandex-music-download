FROM ubuntu:14.04
ENV DEBIAN_FRONTEND=noninteractive LANG=en_US.UTF-8 LC_ALL=C.UTF-8 LANGUAGE=en_US.UTF-8
RUN apt-get update
RUN apt-get -y install perl cpanminus build-essential
COPY src /src
RUN ["cpanm", "Mozilla::CA"]
RUN ["cpanm", "LWP::UserAgent"]
RUN ["cpanm", "HTTP::Cookies"]
RUN ["cpanm", "HTML::Entities"]
RUN ["cpanm", "MP3::Tag"]
RUN ["cpanm", "Getopt::Long::Descriptive"]
RUN apt-get -y  install libssl-dev
RUN ["cpanm", "--force","LWP::Protocol::https"]
ENTRYPOINT [ "/src/ya.pl" ]

