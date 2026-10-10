# Stage 1: the build kitchen. Full JDK and Maven, used only to build the JAR.
FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /app

# Copy the shopping list first and download libraries.
# Docker caches this step, so it only reruns when pom.xml changes.
COPY pom.xml .
RUN mvn -B -q dependency:go-offline

# Now copy the code and build the JAR. Tests run in the pipeline, not here.
COPY src ./src
RUN mvn -B -q clean package -DskipTests

# Stage 2: the food truck. Only the Java runtime (JRE), no compiler.
FROM eclipse-temurin:21-jre

# Our own labels, so registries show this project's details, not the base image's.
LABEL org.opencontainers.image.title="spring-boot-devops-lab"
LABEL org.opencontainers.image.description="Spring Boot service built, containerised and deployed with zero-downtime DevOps practices"
LABEL org.opencontainers.image.source="https://github.com/threejay20/spring-boot-devops-lab"

WORKDIR /app

# Run as a normal user, not root.
RUN useradd --system --uid 1001 appuser

# Copy only the finished JAR out of the build kitchen.
COPY --from=build /app/target/*.jar app.jar
USER appuser

# Heap gets 75% of the container's memory limit; the rest is left for non-heap.
ENV JAVA_TOOL_OPTIONS="-XX:MaxRAMPercentage=75"

EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]