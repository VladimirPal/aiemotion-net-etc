FROM node:24-alpine

# Support custom branch of the js-sdk. This also helps us build images of element-web develop.
ARG USE_CUSTOM_SDKS=false
ARG JS_SDK_REPO="https://github.com/matrix-org/matrix-js-sdk.git"
ARG JS_SDK_BRANCH="master"

RUN apk add --no-cache bash jq moreutils git build-base python3 py3-pip

WORKDIR /app

COPY . /app
# Use Corepack-managed package managers (pnpm/yarn) inside the builder container.
RUN corepack enable

RUN mkdir -p /app/webapp
RUN if [ -f /app/config.sample.json ]; then cp /app/config.sample.json /app/webapp/config.json; fi

CMD ["bash"]
