# Use a lightweight Python image
FROM python:3.12-slim

# Set the working directory
WORKDIR /app

# Copy application code
COPY . /app/

# Copy requirements file and install dependencies
COPY requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r /app/requirements.txt

# Add a non-root user
RUN useradd -m appuser
USER appuser


# Copy the service account key (bind mount in production for security)
# COPY key.json /app/key.json

# Set up Google Cloud authentication
# ENV GOOGLE_APPLICATION_CREDENTIALS="/app/key.json"
# ENV PYTHONUNBUFFERED=1

# Health check (if applicable)
# HEALTHCHECK --interval=30s --timeout=5s \
#     CMD curl --fail http://localhost:8080/health || exit 1

# Expose port (if applicable)
EXPOSE 8080

# Run the application
ENTRYPOINT ["python", "main.py"]
