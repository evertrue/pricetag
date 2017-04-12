FROM registry.evertrue.com/evertrue/passenger-ruby24:master-19
MAINTAINER Eric Herot <eric.herot@evertrue.com>

WORKDIR /home/app/webapp

ARG BUNDLE_GEM__FURY__IO

CMD ["/sbin/my_init"]

EXPOSE 8080

COPY config/image.yml /home/app/webapp/image.yml
COPY nginx.conf /etc/nginx/sites-enabled/default

COPY Gemfile* ./
RUN gem install bundler && \
    chown -R app ./ && \
    /sbin/setuser app bundle install --without development test --deployment

COPY . ./
