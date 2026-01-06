# Custom Prometheus Image for DevOps Exam
# Based on official Prometheus image with custom configuration

FROM prom/prometheus:latest

# Metadata
LABEL maintainer="DevOps Exam Candidate"
LABEL description="Prometheus with custom scrape configuration for microservices monitoring"

# Copy custom Prometheus configuration
COPY prometheus.yml /etc/prometheus/prometheus.yml

# Expose Prometheus port
EXPOSE 9090

# Use the default Prometheus entrypoint
# Configuration will be loaded from /etc/prometheus/prometheus.yml
CMD [ "--config.file=/etc/prometheus/prometheus.yml", \
      "--storage.tsdb.path=/prometheus", \
      "--web.console.libraries=/usr/share/prometheus/console_libraries", \
      "--web.console.templates=/usr/share/prometheus/consoles", \
      "--web.enable-lifecycle" ]
