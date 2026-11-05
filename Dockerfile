# Сервер ИИ-ментора. Сборка: docker build -t ai-mentor .
FROM eclipse-temurin:17-jdk AS build
WORKDIR /src
ENV SERVER_ONLY=1
COPY gradlew settings.gradle.kts build.gradle.kts gradle.properties ./
COPY gradle ./gradle
COPY shared ./shared
COPY server ./server
# в gradle.properties указан JDK с компьютера разработчика – в контейнере используем свой
RUN sed -i '/org.gradle.java.home/d' gradle.properties \
    && chmod +x gradlew \
    && ./gradlew :server:installDist --no-daemon --console=plain

FROM eclipse-temurin:17-jre
WORKDIR /app
COPY --from=build /src/server/build/install/server ./
RUN useradd --system mentor
USER mentor
ENV PORT=8080
EXPOSE 8080
# проверка живости для хостинга: GET /health отвечает "ok"
CMD ["./bin/server"]
