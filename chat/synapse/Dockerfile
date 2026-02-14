FROM synapse-original:latest

RUN apt-get update \
  && apt-get install -y zsh vim git wget curl jq \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

ENTRYPOINT ["/bin/bash","-c","exec python3 /start.py"]
