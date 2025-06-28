# Используем минимальный Alpine вместо Ubuntu
FROM alpine:3.18

# Устанавливаем только критически необходимое
RUN apk add --no-cache \
    nodejs \
    npm \
    wget \
    unzip \
    bash \
    wine \
    && rm -rf /var/cache/apk/*

WORKDIR /app

# Копируем только необходимые файлы (НЕ весь проект!)
COPY package*.json ./
COPY tools/ ./tools/
COPY tgstation.dme ./
COPY BYOND/ ./BYOND/

# Устанавливаем только production зависимости
RUN npm ci --only=production && npm cache clean --force

# Установка BYOND из локальной папки
RUN mkdir -p /usr/local/byond && \
    cp -r BYOND/* /usr/local/byond/ && \
    chmod +x /usr/local/byond/bin/*.exe

# Создаем Wine wrapper
RUN echo '#!/bin/bash\nwine /usr/local/byond/bin/dm.exe "$@"' > /usr/local/bin/dm && \
    chmod +x /usr/local/bin/dm && \
    ln -sf /usr/local/bin/dm /usr/local/bin/DreamMaker

# Копируем исходники только перед сборкой
COPY . .

# Сборка (с очисткой после)
RUN node tools/build/build.js tgui --skip-icon-cutter && \
    node tools/build/build.js dm --skip-icon-cutter && \
    rm -rf node_modules/.cache && \
    rm -rf tools/build/node_modules && \
    rm -rf /tmp/*

EXPOSE 1337

CMD ["wine", "/usr/local/byond/bin/dreamdaemon.exe", "tgstation.dmb", "-port", "1337", "-trusted"]
