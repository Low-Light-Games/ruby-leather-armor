ARG RUBY_VERSION=3.3.1
FROM registry.docker.com/library/ruby:$RUBY_VERSION-slim

# Install OS deps, Node & Yarn
RUN apt-get update -y && \
    apt-get install -y --no-install-recommends \
      build-essential \
      curl \
      git \
      libpq-dev \
      nodejs \
      npm \
      # Playwright/Chromium dependencies
      libglib2.0-0 \
      libnss3 \
      libnspr4 \
      libatk1.0-0 \
      libatk-bridge2.0-0 \
      libcups2 \
      libdrm2 \
      libxkbcommon0 \
      libxcomposite1 \
      libxdamage1 \
      libxfixes3 \
      libxrandr2 \
      libgbm1 \
      libasound2 \
      libpango-1.0-0 \
      libcairo2 \
      libx11-6 \
      libx11-xcb1 \
      libxcb1 \
      libxext6 && \
    npm install -g yarn && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

ENV BUNDLE_PATH=/bundle

# Install Ruby & JS deps first (good layer caching — only re-runs on lockfile changes)
COPY Gemfile Gemfile.lock package.json yarn.lock ./
RUN bundle install
RUN yarn install && npx playwright install chromium

# Install evaluator Node.js dependencies (separate layer for caching)
COPY evaluator/package.json evaluator/package-lock.json ./evaluator/
RUN cd evaluator && npm install --omit=dev

# Copy full app source before anything that needs it
COPY . .

# Ensure no stale Puma restart/pid files are baked into the image
RUN rm -f tmp/pids/server.pid tmp/restart.txt

# RAILS_ENV=production triggers asset precompilation; set to development in
# dev compose (via build.args) to skip it entirely — the bind mount and
# bin/dev watcher handle assets locally.
ARG RAILS_ENV=production
# RAILS_MASTER_KEY is only used during this RUN step and is never written to
# ENV, so it won't appear in `docker inspect` or image layers.
ARG RAILS_MASTER_KEY

RUN if [ "$RAILS_ENV" = "production" ] || [ "$RAILS_ENV" = "staging" ]; then \
      SECRET_KEY_BASE_DUMMY=1 \
      RAILS_MASTER_KEY=${RAILS_MASTER_KEY} \
      RAILS_ENV=production \
      bundle exec rails assets:precompile; \
    fi

# Production default — dev compose overrides this with `command: ./bin/dev`
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
