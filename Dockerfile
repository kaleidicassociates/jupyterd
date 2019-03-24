FROM dlanguage/dmd

RUN \
  apt-get update && apt-get install -y \
    git \
    libzmq3-dev \
    python3 python3-pip
RUN pip3 install notebook

RUN git clone https://github.com/kaleidicassociates/jupyterd.git /jupyterd
RUN mkdir -p /usr/share/jupyter/kernels/d
RUN cp /jupyterd/kernel.json /usr/share/jupyter/kernels/d

WORKDIR /jupyterd

RUN dub build && cp ./jupyterd /usr/sbin

WORKDIR /notebook

RUN echo "#!/bin/sh\n\njupyter-notebook -y --no-browser \$@" > /bin/notebook && chmod +x /bin/notebook

ENTRYPOINT ["/bin/notebook"]
CMD ["--ip", "0.0.0.0", "--NotebookApp.token=", "--allow-root"]
