# Используем Ubuntu 22.04 для поддержки GLIBC 2.35
FROM ubuntu:22.04

# Предотвращаем интерактивные запросы
ENV DEBIAN_FRONTEND=noninteractive

# Устанавливаем системные зависимости
RUN apt-get update && apt-get install -y \
    wget \
    unzip \
    curl \
    gcc \
    g++ \
    libc6-dev \
    libssl3 \
    python3 \
    python3-pip \
    git \
    make \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*

# Устанавливаем Node.js 18
RUN curl -fsSL https://deb.nodesource.com/setup_18.x | bash - && \
    apt-get install -y nodejs

# Устанавливаем рабочую директорию
WORKDIR /app

# Копируем весь проект
COPY . .

# Install bun (required for tgui build)
RUN curl -fsSL https://bun.sh/install | bash && \
    ln -s /root/.bun/bin/bun /usr/local/bin/bun

# Проверяем версию GLIBC
RUN echo "=== GLIBC VERSION CHECK ===" && \
    ldd --version

# Устанавливаем BYOND
RUN echo "=== INSTALLING BYOND ===" && \
    if [ -d "BYOND" ]; then \
        echo "Found local BYOND directory" && \
        if [ -d "BYOND/byond" ]; then \
            cp -r BYOND/byond /usr/local/byond; \
        elif [ -d "BYOND/bin" ]; then \
            mkdir -p /usr/local/byond && \
            cp -r BYOND/* /usr/local/byond/; \
        else \
            cp -r BYOND /usr/local/byond; \
        fi && \
        find /usr/local/byond -type f -exec chmod +x {} \; && \
        echo "BYOND installed from local directory"; \
    else \
        echo "Downloading BYOND..." && \
        wget -O byond.zip "http://www.byond.com/download/build/515/515.1637_byond_linux.zip" && \
        unzip -q byond.zip && \
        mv byond /usr/local/byond && \
        find /usr/local/byond -type f -exec chmod +x {} \; && \
        rm byond.zip && \
        echo "BYOND downloaded and installed"; \
    fi

# Проверяем установку BYOND
RUN echo "=== BYOND CHECK ===" && \
    find /usr/local/byond -name "dm" -type f && \
    find /usr/local/byond -name "dreamdaemon" -type f

# Настраиваем переменные окружения
ENV PATH="/usr/local/byond/bin:${PATH}"

# ВАЖНО: Выполняем сборку проекта с пропуском icon-cutter
RUN echo "=== BUILDING PROJECT WITH SKIP-ICON-CUTTER ===" && \
    export PATH="/usr/local/byond/bin:$PATH" && \
    if [ -f "tools/build/build.js" ]; then \
        echo "Using build.js with skip-icon-cutter" && \
        node tools/build/build.js build --skip-icon-cutter; \
    elif [ -f "tools/bootstrap/javascript" ]; then \
        echo "Using bootstrap build" && \
        bash tools/bootstrap/javascript; \
    else \
        echo "Direct DM compilation fallback" && \
        dm tgstation.dme; \
    fi

# Проверяем результат сборки
RUN echo "=== FINAL BUILD CHECK ===" && \
    ls -la *.dmb *.rsc 2>/dev/null || echo "Build files check failed" && \
    if [ -f "tgstation.dmb" ]; then \
        echo "SUCCESS: Build completed" && \
        ls -lh tgstation.dmb; \
    else \
        echo "ERROR: Build failed" && \
        exit 1; \
    fi

# Открываем порты
EXPOSE 1337

# Создаем startup скрипт
RUN cat > /app/start_server.sh << 'EOF'
#!/bin/bash
echo "=== SS13 SERVER STARTUP ==="
echo "Current directory: $(pwd)"
echo "Available files:"
ls -la

# Проверяем наличие dmb файла
if [ ! -f "tgstation.dmb" ]; then
    echo "ERROR: tgstation.dmb not found"
    echo "Available files:"
    ls -la
    exit 1
fi

# Ищем dreamdaemon
DAEMON_PATH=$(find /usr/local -name "dreamdaemon" -type f 2>/dev/null | head -1)
if [ -z "$DAEMON_PATH" ]; then
    echo "ERROR: dreamdaemon not found"
    find /usr/local -name "*daemon*" 2>/dev/null
    exit 1
fi

echo "Found dreamdaemon: $DAEMON_PATH"
echo "Starting SS13 server on port 1337..."

# Запускаем сервер
exec "$DAEMON_PATH" tgstation.dmb -port 1337 -trusted -verbose
EOF

RUN chmod +x /app/start_server.sh

# Команда запуска
CMD ["/app/start_server.sh"]
