# Use Python slim image
FROM python:3.9-slim

# Set working directory
WORKDIR /app

# Copy dependencies file
COPY requirements.txt .

# Install dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy all app files
COPY . .

# Run the Flask app
CMD ["python", "app.py"]
