# Сервер ИИ-ментора (Swift + Vapor). Сборка: docker build -t ai-mentor .
FROM swift:6.1-noble AS build
WORKDIR /src
COPY server/Package.swift server/Package.resolved ./
RUN swift package resolve
COPY server/Sources ./Sources
RUN swift build -c release --product mentor-server --static-swift-stdlib \
    && mkdir /app \
    && cp "$(swift build -c release --show-bin-path)/mentor-server" /app/ \
    && cp -R "$(swift build -c release --show-bin-path)"/*.resources /app/

FROM ubuntu:noble
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates libcurl4 libxml2 tzdata \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --system mentor
WORKDIR /app
COPY --from=build /app ./
USER mentor
ENV PORT=8080
EXPOSE 8080
# проверка живости для хостинга: GET /health отвечает "ok"
CMD ["./mentor-server"]
