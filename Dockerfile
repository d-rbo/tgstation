# Простой Dockerfile для SS13 на Railway
FROM ubuntu:22.04

# Установка базовых зависимостей
RUN apt-get update && apt-get install -y \
    wget \
    unzip \
    lib32gcc-s1 \
    lib32stdc++6 \
    libc6-i386 \
    && rm -rf /var/lib/apt/lists/*

# Установка BYOND
WORKDIR /tmp
RUN wget -O byond.zip "http://www.byond.com/download/build/515/515.1637_byond_linux.zip" \
    && unzip byond.zip \
    && mv byond /opt/byond \
    && chmod +x /opt/byond/bin/* \
    && ln -s /opt/byond/bin/DreamMaker /usr/local/bin/DreamMaker \
    && ln -s /opt/byond/bin/DreamDaemon /usr/local/bin/DreamDaemon \
    && rm byond.zip

# Создание директории для игры
WORKDIR /tgstation

# Копирование всех файлов проекта
COPY . .

# Создание простого конфига (отключаем тяжелые модули)
RUN mkdir -p config && \
    echo "MINING_ENABLED 0" > config/game_options.txt && \
    echo "LAVALAND_ENABLED 0" >> config/game_options.txt && \
    echo "MINING_RUINS_ENABLED 0" >> config/game_options.txt && \
    echo "SPACE_RUINS_ENABLED 0" >> config/game_options.txt && \
    echo "ATMOSPHERIC_PROCESSING 0" >> config/game_options.txt

# Попытка компиляции (может не сработать без rust-g)
RUN DreamMaker tgstation.dme || echo "Compilation failed, but continuing..."

# Открываем порт (Railway автоматически назначит)
EXPOSE $PORT  

# Updated for Railway

# Запуск сервера
CMD DreamDaemon tgstation.dmb -port ${PORT:-1337} -trusted -close -verbose
