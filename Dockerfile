# syntax=docker/dockerfile:1
# check=error=true

# This Dockerfile is designed for production, not development. Use with Kamal or build'n'run by hand:
# docker build -t bonid .
# docker run -d -p 80:80 -e RAILS_MASTER_KEY=<value from config/master.key> --name bonid bonid

# For a containerized dev environment, see Dev Containers: https://guides.rubyonrails.org/getting_started_with_devcontainer.html

# Make sure RUBY_VERSION matches the Ruby version in .ruby-version
# syntax=docker/dockerfile:1
# check=error=true

# Stage 1: Base Ruby image with build dependencies
FROM ruby:3.2.2 AS base

ENV BUNDLER_VERSION=2.5.6 \
  RAILS_ENV=production \
  NODE_ENV=production \
  RUNTIME_DEPS="libvips libpq5" \
  BUILD_DEPS="build-essential libpq-dev libvips-dev git curl libyaml-dev pkg-config libffi-dev node-gyp python-is-python3"

RUN apt-get update -qq && \
  apt-get install -y --no-install-recommends $RUNTIME_DEPS $BUILD_DEPS && \
  rm -rf /var/lib/apt/lists/* /var/cache/apt/archives

# Install Node.js & Yarn for esbuild
RUN curl -sL https://deb.nodesource.com/setup_18.x | bash - && \
    apt-get install -y nodejs && \
    npm install --global yarn

# Stage 2: Install Ruby gems
FROM base AS build

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN gem install bundler -v "$BUNDLER_VERSION" && bundle install --jobs 4 --without development test

# Stage 3: Copy app, build JS, precompile assets
FROM build AS app

WORKDIR /app
COPY . .

# JS bundling + Rails asset precompile
RUN yarn install --frozen-lockfile && \
    yarn build && \
    bundle exec rake assets:precompile

# Stage 4: Runtime image
FROM base

WORKDIR /app

COPY --from=app /app /app
COPY --from=build /usr/local/bundle /usr/local/bundle

EXPOSE 3000

CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
