# Multi-stage build для SS13 TGStation на Railway
# Stage 1: Builder - собираем проект
FROM tgstation/byond:515 as builder

# Устанавливаем рабочую директорию
WORKDIR /app

# Устанавливаем Node.js для TGUI (если нужен более новый)
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    && curl -fsSL https://deb.nodesource.com/setup_18.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# Копируем файлы для сборки (оптимизированный порядок для Docker cache)
COPY package*.json ./
COPY tools/ ./tools/
COPY tgui/ ./tgui/

# Устанавливаем bun для TGUI сборки
RUN curl -fsSL https://bun.sh/install | bash && \
    ln -s /root/.bun/bin/bun /usr/local/bin/bun

# Копируем остальные исходники
COPY . .

# Собираем проект
RUN echo "=== BUILDING TGUI ===" && \
    node tools/build/build.js tgui --skip-icon-cutter && \
    echo "=== BUILDING DM ===" && \
    node tools/build/build.js dm --skip-icon-cutter && \
    # Проверяем результат сборки
    if [ -f "tgstation.dmb" ]; then \
        echo "✅ BUILD SUCCESS: tgstation.dmb created"; \
        ls -lh tgstation.dmb; \
    else \
        echo "❌ BUILD FAILED: tgstation.dmb not found"; \
        exit 1; \
    fi

# Stage 2: Runtime - минимальный образ для запуска
FROM tgstation/byond:515 as runtime

# Создаем рабочую директорию
WORKDIR /app

# Копируем только необходимые файлы из builder stage
COPY --from=builder /app/tgstation.dmb ./
COPY --from=builder /app/tgstation.rsc ./
COPY --from=builder /app/config/ ./config/
COPY --from=builder /app/data/ ./data/
COPY --from=builder /app/maps/ ./maps/
COPY --from=builder /app/sound/ ./sound/
COPY --from=builder /app/icons/ ./icons/
COPY --from=builder /app/tgui/public/ ./tgui/public/

# Создаем директории для логов и данных (если нужны)
RUN mkdir -p /app/data/logs /app/data/player_saves

# Создаем оптимизированный startup script
RUN cat > /app/start_server.sh << 'EOF'
#!/bin/bash
set -e

echo "🚀 Starting SS13 TGStation Server"
echo "=================================="

# Проверяем наличие .dmb файла
if [ ! -f "tgstation.dmb" ]; then
    echo "❌ ERROR: tgstation.dmb not found"
    ls -la
    exit 1
fi

# Проверяем размер файла
DMB_SIZE=$(stat -f%z tgstation.dmb 2>/dev/null || stat -c%s tgstation.dmb 2>/dev/null || echo "0")
if [ "$DMB_SIZE" -lt 1000000 ]; then
    echo "❌ ERROR: tgstation.dmb seems too small ($DMB_SIZE bytes)"
    exit 1
fi

echo "✅ Found tgstation.dmb (${DMB_SIZE} bytes)"

# Настройки для Railway
export PORT=${PORT:-1337}
export BYOND_WORLD_LOG="/app/data/logs/world.log"

# Создаем директорию для логов
mkdir -p /app/data/logs

echo "🌐 Starting server on port $PORT"
echo "📁 Working directory: $(pwd)"
echo "🗂️  Files in directory:"
ls -la

# Запускаем DreamDaemon
exec DreamDaemon tgstation.dmb -port $PORT -trusted -verbose -log /app/data/logs/server.log
EOF

# Делаем скрипт исполняемым
RUN chmod +x /app/start_server.sh

# Настройки пользователя (Railway security)
RUN useradd -m -u 1001 ss13user && \
    chown -R ss13user:ss13user /app
USER ss13user

# Открываем порт (Railway автоматически определит)
EXPOSE $PORT

# Проверка здоровья контейнера
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD pgrep -f "DreamDaemon" || exit 1

# Команда запуска
CMD ["/app/start_server.sh"]
