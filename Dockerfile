# === Stage 1: Base Ruby image with build dependencies ===
ARG RUBY_VERSION=3.2.2
FROM ruby:${RUBY_VERSION} AS base

ENV BUNDLER_VERSION=2.5.6 \
    RAILS_ENV=production \
    NODE_ENV=production \
    NODE_OPTIONS=--max-old-space-size=4096 \
    RUNTIME_DEPS="libvips libpq5" \
    BUILD_DEPS="build-essential libpq-dev libvips-dev git curl libyaml-dev pkg-config libffi-dev node-gyp python-is-python3"

RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends $RUNTIME_DEPS $BUILD_DEPS && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives

# Install Node.js 18.20.8 & Yarn
RUN curl -sL https://deb.nodesource.com/setup_18.x | bash - && \
    apt-get install -y nodejs=18.20.8-1nodesource1 && \
    npm install --global yarn && \
    yarn config set registry https://registry.yarnpkg.com

# === Stage 2: Install Ruby gems ===
FROM base AS build

WORKDIR /app
COPY Gemfile Gemfile.lock ./
ARG BUNDLERV
RUN gem install bundler -v "${BUNDLERV:-$BUNDLER_VERSION}" && \
    bundle config set --local without 'development test' && \
    bundle install --jobs 4

# === Stage 3: Copy app, build JS, precompile assets ===
FROM build AS app

WORKDIR /app
COPY package.json yarn.lock ./
RUN yarn install --frozen-lockfile

# Install esbuild for JS bundling
RUN yarn add esbuild && \
    yarn esbuild --version

# Copy the rest of the app
COPY . .

# Check if main JS entry point exists
RUN ls -la app/javascript && \
    test -f app/javascript/application.js || (echo "ERROR: app/javascript/application.js not found" && exit 1)

# Build JS and CSS assets
RUN yarn build && ls -la app/assets/builds

# Precompile Rails assets using ENV-injected RAILS_MASTER_KEY or secret
RUN if [ -f /run/secrets/rails_master_key ]; then \
      export RAILS_MASTER_KEY=$(cat /run/secrets/rails_master_key); \
    fi && \
    bundle exec rake assets:precompile --trace

# === Stage 4: Final runtime image ===
FROM base

WORKDIR /app
COPY --from=app /app /app
COPY --from=build /usr/local/bundle /usr/local/bundle

EXPOSE 3000
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]