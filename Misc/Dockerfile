FROM swift:5.4

RUN apt-get -y update \
 && apt-get -yy install llvm vim lsof valgrind linux-tools-generic siege curl strace \
 && rm -f /usr/local/bin/perf \
 && perf=$(find /usr/lib/linux-tools/*/perf | head -1) \
 && ln -s "$perf" /usr/local/bin/perf
