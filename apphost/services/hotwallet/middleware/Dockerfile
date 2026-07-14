FROM python:3.14-slim@sha256:b877e50bd90de10af8d82c57a022fc2e0dc731c5320d762a27986facfc3355c1
WORKDIR /app
COPY requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r /app/requirements.txt
COPY src /app/src
RUN useradd -u 1000 -m app
USER 1000
EXPOSE 8080
CMD ["uvicorn", "src.main:app", "--host=0.0.0.0", "--port=8080"]
