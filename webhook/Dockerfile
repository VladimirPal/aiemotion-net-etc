FROM golang:alpine AS build
WORKDIR /go/src/webhook
RUN apk add --update -t build-deps libc-dev gcc libgcc
COPY . .
RUN go get -d -v
RUN CGO_ENABLED=0 go build -ldflags="-s -w" -o /usr/local/bin/webhook

FROM docker:cli
COPY --from=build /usr/local/bin/webhook /usr/local/bin/webhook
WORKDIR /etc/webhook
VOLUME ["/etc/webhook"]
EXPOSE 9000
ENTRYPOINT ["/usr/local/bin/webhook"]
