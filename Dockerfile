FROM alpine:latest
ENV LANG=en_US.UTF-8 LC_ALL=C.UTF-8 LANGUAGE=en_US.UTF-8
RUN apk --update add perl perl-app-cpanminus make unzip
RUN apk add perl-libwww perl-lwp-protocol-https perl-http-cookies perl-html-parser perl-getopt-long-descriptive perl-archive-zip \
    --repository=http://dl-cdn.alpinelinux.org/alpine/edge/testing/
RUN ["cpanm", "MP3::Tag", "File::Util"]
COPY src /src
ENTRYPOINT [ "/src/ya.pl" ]
