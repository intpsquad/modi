# Spring Boot API 이미지. `docker build` 하나로 자체완결되게 multi-stage 로 짠다 —
# CI 없이 로컬에서도 똑같이 재현돼야 디버깅이 된다.

# ---------- build ----------
FROM eclipse-temurin:21-jdk AS build
WORKDIR /build

# 래퍼와 빌드 스크립트를 먼저 복사해 의존성 해석을 별도 레이어로 만든다.
# 소스만 바뀐 커밋에서는 이 레이어가 캐시에 남아 재빌드가 훨씬 빠르다.
COPY gradlew ./
COPY gradle ./gradle
COPY settings.gradle build.gradle ./
RUN chmod +x ./gradlew && ./gradlew --no-daemon dependencies

COPY src ./src
# 테스트는 CI 의 `server` 잡에서 이미 돌았다. 여기서 또 돌리면
# Testcontainers 가 docker.sock 없는 빌드 컨텍스트에서 죽는다.
# bootJar 만 실행하므로 build/libs 에는 실행 가능한 부트 jar 하나만 남는다(-plain.jar 없음).
RUN ./gradlew --no-daemon clean bootJar -x test

# ---------- runtime ----------
FROM eclipse-temurin:21-jre
WORKDIR /app

# curl 은 compose healthcheck(/actuator/health)와 컨테이너 안 디버깅에 쓴다.
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl \
 && rm -rf /var/lib/apt/lists/*

# 비루트 실행.
RUN groupadd --system --gid 1001 spring \
 && useradd --system --uid 1001 --gid spring spring

COPY --from=build /build/build/libs/*.jar app.jar
USER spring

EXPOSE 8080
# 컨테이너 메모리 한도를 기준으로 힙을 잡는다(고정 -Xmx 는 한도를 바꿀 때 같이 안 바뀐다).
ENTRYPOINT ["java", "-XX:MaxRAMPercentage=75.0", "-jar", "/app/app.jar"]
