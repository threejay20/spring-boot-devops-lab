# spring-boot-devops-lab

A small Spring Boot service, used to practise the full path a Java service takes to production: build, containerise, deploy with zero downtime, and run safely on Kubernetes.

## What's here so far

| Stage | What it covers | Status |
| --- | --- | --- |
| 1. Build | Spring Boot app with a `/hello` endpoint and Actuator health checks, built with Maven | Done |
| 2. Containerise | Multi-stage Dockerfile, JRE-only runtime image, non-root user, container-aware memory settings | Done |
| 3. Deploy | Helm chart on a local Kubernetes cluster with readiness probes and graceful shutdown | Next |
| 4. Automate | GitHub Actions pipeline to build, test and publish the image | Planned |

## Run it

With Maven:

```bash
./mvnw clean package
java -jar target/demo-0.0.1-SNAPSHOT.jar
curl localhost:8080/hello
curl localhost:8080/actuator/health/readiness
```

With Docker:

```bash
docker build -t spring-boot-devops-lab:1.0 .
docker run -d -p 8080:8080 --name app spring-boot-devops-lab:1.0
curl localhost:8080/hello
```

Settings can change without a rebuild. For example, `SERVER_PORT=9090` moves the app to port 9090 using the same JAR or image.

## Design decisions

**Two-stage Dockerfile.** Maven and the full JDK build the JAR in the first stage, and only the JAR is copied into a JRE-only image. The final image has no compiler, build tools or source code, and comes out at about 138 MB.

**Dependency caching.** `pom.xml` is copied and dependencies downloaded before the source code, so code changes don't trigger a full re-download.

**Non-root user.** The app runs as `appuser`, not root.

**Container-aware memory.** The heap is set with `-XX:MaxRAMPercentage=75` instead of a fixed `-Xmx`, so it scales with the container's memory limit and leaves room for non-heap memory.

## Memory experiment

The same image, run in a 256 MB container with two different heap settings:

| Heap setting | Result |
| --- | --- |
| Fixed `-Xmx512m` (bigger than the container) | `OOMKilled=true`, exit code 137, and no `OutOfMemoryError` in the app logs: the container was killed from outside |
| `-XX:MaxRAMPercentage=75` | Ran normally and answered requests |

Exit code 137 with no error in the logs points to the container's memory limit, not the app's heap.

## Tech

Java 21, Spring Boot, Maven, Docker, Eclipse Temurin
