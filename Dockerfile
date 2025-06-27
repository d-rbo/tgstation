# Простой Dockerfile для SS13 на Railway
FROM ubuntu:22.04

# Установка базовых зависимостей + Node.js для JavaScript
RUN apt-get update && apt-get install -y \
    wget \
    unzip \
    lib32gcc-s1 \
    lib32stdc++6 \
    libc6-i386 \
    make \
    python3 \
    nodejs \
    npm \
    && rm -rf /var/lib/apt/lists/*

# Копирование проекта (включая BYOND)
COPY . /app
WORKDIR /app

# Настройка BYOND из локальной папки
RUN if [ -d "BYOND" ]; then \
        echo "Using local BYOND from project" && \
        cp -r BYOND /usr/local/byond && \
        chmod +x /usr/local/byond/bin/*; \
    else \
        echo "ERROR: BYOND directory not found in project"; \
        exit 1; \
    fi

# Настройка PATH
ENV PATH="/usr/local/byond/bin:${PATH}"

# Копирование проекта
COPY . /app
WORKDIR /app

# ОТЛАДКА - смотрим что у нас есть
RUN echo "=== ROOT DIRECTORY ===" && ls -la
RUN echo "=== TOOLS DIRECTORY ===" && ls -la tools/ 2>/dev/null || echo "No tools directory"
RUN echo "=== TOOLS/BUILD DIRECTORY ===" && ls -la tools/build/ 2>/dev/null || echo "No tools/build directory"
RUN echo "=== TOOLS/BOOTSTRAP DIRECTORY ===" && ls -la tools/bootstrap/ 2>/dev/null || echo "No tools/bootstrap directory"

# Проверяем какие файлы найдены и выполняем с отладкой
RUN if [ -f "tools/bootstrap/javascript" ]; then \
        echo "=== FOUND: tools/bootstrap/javascript ===" && \
        chmod +x tools/bootstrap/javascript && \
        echo "Executing: tools/bootstrap/javascript tools/build/build.js" && \
        tools/bootstrap/javascript tools/build/build.js 2>&1 || echo "ERROR in bootstrap/javascript"; \
    elif [ -f "tools/build/build.js" ]; then \
        echo "=== FOUND: tools/build/build.js ===" && \
        echo "Executing: node tools/build/build.js" && \
        node tools/build/build.js 2>&1 || echo "ERROR in build.js"; \
    elif [ -f "tools/build/build" ]; then \
        echo "=== FOUND: tools/build/build ===" && \
        chmod +x tools/build/build && \
        echo "Executing: tools/build/build" && \
        tools/build/build 2>&1 || echo "ERROR in build script"; \
    else \
        echo "=== NO BUILD SCRIPTS FOUND, USING DM FALLBACK ===" && \
        echo "Executing: /usr/local/byond/bin/dm tgstation.dme" && \
        /usr/local/byond/bin/dm tgstation.dme 2>&1 || echo "ERROR in dm compilation"; \
    fi

# Запуск сервера
EXPOSE 1337
CMD ["/usr/local/byond/bin/dreamdaemon", "tgstation.dmb", "1337", "-trusted"]
