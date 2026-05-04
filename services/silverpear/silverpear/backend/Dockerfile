FROM golang:1.24-alpine AS builder

WORKDIR /src/backend

COPY backend/go.mod ./

RUN go mod download

COPY backend/*.go ./

RUN go mod tidy && go build -o /out/silverpear-backend .

FROM alpine:3.21

WORKDIR /app

COPY --from=builder /out/silverpear-backend /usr/local/bin/silverpear-backend
COPY migrations /app/migrations

ENV SILVERPEAR_ADDR=0.0.0.0:8080
ENV SILVERPEAR_DB_URL=postgres://silverpear:silverpear@db:5432/silverpear?sslmode=disable
ENV SILVERPEAR_MIGRATIONS_DIR=/app/migrations

EXPOSE 8080

CMD ["silverpear-backend"]
