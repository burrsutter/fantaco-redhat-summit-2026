# Multi-stage build Dockerfile using Red Hat UBI9 OpenJDK 21

# Build stage
FROM registry.access.redhat.com/ubi9/openjdk-21:latest AS build
WORKDIR /app

# Ensure the non-root user (default in UBI images) owns the working directory
USER root
RUN chown -R 185:185 /app
USER 185

COPY pom.xml .
COPY src ./src
RUN mvn clean package -DskipTests

# Runtime stage
FROM registry.access.redhat.com/ubi9/openjdk-21-runtime:latest
WORKDIR /app
COPY --from=build /app/target/*.jar app.jar
EXPOSE 8083
ENTRYPOINT ["java", "-jar", "app.jar"]
