FROM ruby:3.4-alpine

#RUN apt-get update && apt-get install -y inotify-tools imagemagick && rm -rf /var/lib/apt/lists/*

#RUN apk add --no-cache inotify-tools imagemagick
RUN apk add --no-cache \
    imagemagick \
    imagemagick-dev \
    libjpeg-turbo \
    libpng \
    ghostscript \
    tiff \
    && rm -rf /var/cache/apk/*

#RUN gem install mini_magick rb-inotify

WORKDIR /app

COPY Gemfile rotater.rb .
RUN bundle install

#VOLUME ["/config", "/images", "/output"]

CMD ["ruby", "rotater.rb"]
