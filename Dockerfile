FROM ubuntu:18.04
ENV DEBIAN_FRONTEND=noninteractive LANG=en_US.UTF-8 LC_ALL=C.UTF-8 LANGUAGE=en_US.UTF-8
RUN apt-get update
RUN apt-get -y install perl cpanminus make
RUN apt-get -y install libwww-perl liblwp-protocol-https-perl libhttp-cookies-perl libhtml-parser-perl libmp3-tag-perl libgetopt-long-descriptive-perl libarchive-zip-perl
RUN ["cpanm", "Mozilla::CA", "File::Util"]
COPY src /src
ENTRYPOINT [ "/src/ya.pl" ]
