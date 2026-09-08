# Migrating to a distroless base image

[Distroless](https://github.com/GoogleContainerTools/distroless) images (`gcr.io/distroless/*`)
contain only your app and its runtime dependencies — no shell, package manager, or OS utilities.
That removes most of the CVE surface a full `debian`/`alpine`/`ubuntu` base carries, and shrinks
the image. Use a **multi-stage build**: build on a full image, copy only the artifact into a
distroless final stage.

## Choosing the base

| App | Distroless image |
|-----|------------------|
| Static Go binary (`CGO_ENABLED=0`) | `gcr.io/distroless/static-debian12` |
| Dynamically-linked binary (glibc) | `gcr.io/distroless/base-debian12` |
| C/C++/Rust needing libgcc/libstdc++ | `gcr.io/distroless/cc-debian12` |
| Java | `gcr.io/distroless/java21-debian12` (also `java17`) |
| Node.js | `gcr.io/distroless/nodejs22-debian12` (also `nodejs20`) |
| Python | `gcr.io/distroless/python3-debian12` |

Tags on all of the above: `:nonroot` (runs as UID 65532 — prefer it), `:debug` (adds a busybox
shell for troubleshooting). **Pin the Debian version** (`-debian12`) and ideally a digest — the
bare `gcr.io/distroless/static` alias now floats to `debian13`.

## Patterns

Go (static):
```dockerfile
FROM golang:1.23 AS build
WORKDIR /src
COPY . .
RUN CGO_ENABLED=0 go build -o /app ./cmd/app

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /app /app
USER nonroot:nonroot
ENTRYPOINT ["/app"]
```

Node.js (the `nodejs` image's ENTRYPOINT is already `node`, so CMD is just the script):
```dockerfile
FROM node:22 AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev
COPY . .

FROM gcr.io/distroless/nodejs22-debian12:nonroot
WORKDIR /app
COPY --from=build /app /app
CMD ["server.js"]
```

Java:
```dockerfile
FROM eclipse-temurin:21-jdk AS build
WORKDIR /src
COPY . .
RUN ./mvnw -q package -DskipTests

FROM gcr.io/distroless/java21-debian12:nonroot
COPY --from=build /src/target/app.jar /app.jar
ENTRYPOINT ["/app.jar"]
```

Python:
```dockerfile
FROM python:3.12-slim AS build
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir --target=/app/deps -r requirements.txt
COPY . .

FROM gcr.io/distroless/python3-debian12:nonroot
WORKDIR /app
ENV PYTHONPATH=/app/deps
COPY --from=build /app /app
CMD ["main.py"]
```

## Caveats

- **No shell / no package manager** in the final image — you can't `RUN apt`/`sh` there, and
  `docker exec ... sh` won't work. Use the `:debug` tag (busybox at `/busybox/sh`) to
  troubleshoot, then switch back.
- **ENTRYPOINT/CMD must be exec (vector) form** `["/app"]`, not shell form — there is no `/bin/sh`.
- **`nonroot` runs as UID 65532** — make sure copied files are readable and bind ports > 1024.
- Language images still bundle their interpreter/runtime (Node, CPython, JRE) — that runtime's
  own CVEs remain, so **keep scanning** after migrating. Re-run `scripts/scan.sh` on the new
  image and compare the counts to prove the improvement.
