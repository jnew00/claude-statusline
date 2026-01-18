# Claude Plan Usage Scraper - Docker Image
# Runs Playwright with xvfb for headless-but-not-really operation

FROM node:20-bookworm

# Install dependencies for Playwright + xvfb + VNC
RUN apt-get update && apt-get install -y --no-install-recommends \
    libnss3 libnspr4 libatk1.0-0 libatk-bridge2.0-0 libcups2 libdrm2 \
    libdbus-1-3 libxkbcommon0 libatspi2.0-0 libxcomposite1 libxdamage1 \
    libxfixes3 libxrandr2 libgbm1 libasound2 libpango-1.0-0 libcairo2 \
    xvfb x11vnc procps curl jq python3 git ca-certificates \
    autocutsel xclip \
    && rm -rf /var/lib/apt/lists/*

# Install noVNC from git
RUN git clone --depth 1 https://github.com/novnc/noVNC.git /opt/novnc \
    && git clone --depth 1 https://github.com/novnc/websockify.git /opt/novnc/utils/websockify \
    && ln -s /opt/novnc/vnc.html /opt/novnc/index.html

# Create app directory
WORKDIR /app

# Copy package files
COPY package*.json ./
COPY tsconfig.json ./

# Install ALL dependencies (including devDependencies for build)
RUN npm ci

# Install Playwright browsers
RUN npx playwright install chromium

# Copy source and build
COPY src/ ./src/
RUN npm run build

# Remove devDependencies after build
RUN npm prune --production

# Copy scripts
COPY docker/entrypoint.sh ./
COPY docker/serve.sh ./

RUN chmod +x entrypoint.sh serve.sh

# Create data directory for persistent storage
RUN mkdir -p /data/playwright-profile /data/output

# Environment variables
ENV DISPLAY=:99
ENV OUTPUT_DIR=/data/output
ENV PROFILE_DIR=/data/playwright-profile
ENV HTTP_PORT=8080
ENV VNC_PORT=5900

# Expose ports
EXPOSE 8080 5900

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:${HTTP_PORT}/plan-usage.json || exit 1

ENTRYPOINT ["./entrypoint.sh"]
CMD ["scrape"]
