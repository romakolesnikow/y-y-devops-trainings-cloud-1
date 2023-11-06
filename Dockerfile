FROM golang:1.21 AS builder

WORKDIR /app

COPY ./catgpt/. /app/

RUN go mod download

#ENV CGO_ENABLED 0

RUN CGO_ENABLED=0 go build -o /app/main

FROM gcr.io/distroless/static-debian12:latest-amd64

WORKDIR /app

COPY --from=builder /app/main .


EXPOSE 8080

CMD ["/app/main"]