# Stage 1: Build
FROM python:3.11-slim AS builder
WORKDIR /api
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# Stage 2: Runtime
FROM python:3.11-slim
WORKDIR /api
RUN useradd --create-home --uid 1001 appuser
COPY --from=builder /install /usr/local
COPY app.py .

USER appuser
EXPOSE 5000
HEALTHCHECK --interval=30s --timeout=3s \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:5000/health')" || exit 1

CMD ["gunicorn", "--bind", "0.0.0.0:5000", "app:app"]
