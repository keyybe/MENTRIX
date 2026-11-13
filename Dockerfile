# Сервер ИИ-ментора (Swift + Vapor). Сборка: docker build -t ai-mentor .
FROM swift:6.4-noble AS build
WORKDIR /src
COPY server/Package.swift server/Package.resolved ./
RUN swift package resolve
COPY server/Sources ./Sources
# тесты в образ не попадают, но без папки SwiftPM не разберёт тестовый таргет из Package.swift
COPY server/Tests ./Tests
# ресурсы (sources.json) лежат рядом с бинарником: в старых версиях SwiftPM – *.resources, в новых – *.bundle
RUN swift build -c release --product mentor-server --static-swift-stdlib \
    && BIN="$(swift build -c release --show-bin-path)" \
    && mkdir /app \
    && cp "$BIN/mentor-server" /app/ \
    && for d in "$BIN"/*.resources "$BIN"/*.bundle; do if [ -e "$d" ]; then cp -R "$d" /app/; fi; done \
    && ls /app | grep -q "^MentorServer_MentorServer\."

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
