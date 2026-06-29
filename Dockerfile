FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app
COPY . /app

ARG INSTALL_DEV=1
RUN python -m pip install --upgrade pip && \
    if [ "$INSTALL_DEV" = "1" ]; then \
        pip install -e ".[dev]"; \
    else \
        pip install "."; \
    fi

CMD ["python", "run.py"]
