# syntax=docker/dockerfile:1
# check=error=true

# This Dockerfile is designed for production, not development. Use with Kamal or build'n'run by hand:
# docker build -t bonid --secret id=rails_master_key,src=config/master.key .
# docker run -d -p 80:80 -e RAILS_MASTER_KEY=<value from config/master.key> --name bonid bonid

# Stage 1: Base Ruby image with build dependencies
FROM ruby:3.2.2 AS base

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

# Stage 2: Install Ruby gems
FROM base AS build

WORKDIR /app
COPY Gemfile Gemfile.lock ./
RUN gem install bundler -v "$BUNDLER_VERSION" && \
    bundle config set --local without 'development test' && \
    bundle install --jobs 4

# Stage 3: Copy app, build JS, precompile assets
FROM build AS app

WORKDIR /app
COPY package.json yarn.lock ./
RUN yarn install --frozen-lockfile

# Install esbuild explicitly
RUN yarn add esbuild && \
    yarn esbuild --version

# Copy the rest of the app
COPY . .

# Debug: List JavaScript files and verify entry point
RUN ls -la app/javascript && \
    test -f app/javascript/application.js || (echo "ERROR: app/javascript/application.js not found" && exit 1)

# Run build and debug output
RUN yarn build && \
    ls -la app/assets/builds

# Precompile assets with RAILS_MASTER_KEY as a secret
RUN --mount=type=secret,id=rails_master_key \
    RAILS_MASTER_KEY=$(cat /run/secrets/rails_master_key) bundle exec rake assets:precompile --trace

# Stage 4: Runtime image
FROM base

WORKDIR /app
COPY --from=app /app /app
COPY --from=build /usr/local/bundle /usr/local/bundle

EXPOSE 3000
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]