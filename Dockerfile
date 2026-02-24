ARG RUBY_VERSION=3.3.1
FROM registry.docker.com/library/ruby:$RUBY_VERSION-slim as base

# Install OS deps, Node & Yarn
RUN apt-get update -y && \
    apt-get install -y --no-install-recommends \
      build-essential \
      curl \
      git \
      libpq-dev \
      nodejs \
      npm \
      # Puppeteer/Chrome dependencies
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
      libcairo2 && \
    npm install -g yarn && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Common env for production image
ENV RAILS_ENV=development \
    NODE_ENV=development \
    BUNDLE_PATH=/bundle

# Install Ruby & JS deps first for better caching
COPY Gemfile Gemfile.lock package.json yarn.lock ./
RUN bundle install
RUN yarn install
RUN bundle exec rails assets:precompile

# Default command: Use bin/dev to run Rails server + JS/CSS watchers
CMD ["./bin/dev"]