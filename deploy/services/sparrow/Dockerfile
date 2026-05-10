# Dockerfile for Sparrow Watch-Only Server
FROM openjdk:17-jre-slim

# Install curl for downloading
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*

# Download latest Sparrow JAR (adjust version as needed)
RUN curl -L -o sparrow.jar https://github.com/sparrowwallet/sparrow/releases/download/1.8.5/Sparrow-1.8.5.jar

# Copy start script
COPY src/start.sh /start.sh
RUN chmod +x /start.sh

# Expose port for web interface
EXPOSE 8080

# Run start script
CMD ["/start.sh"]