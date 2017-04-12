# Pricetag

![Price Tag](https://img.shields.io/badge/price-25.33%2Fhr-lightgray.svg "Price Tag")

A tiny web server that serves up SVG shield price tags for your Mesos apps. The number is based on CPUs requested in the Singularity `request` object.

## Usage

Build it into a docker container.

## Building Using Docker

```
docker build --build-arg BUNDLE_GEM__FURY__IO=$BUNDLE_GEM__FURY__IO -t registry.evertrue.com/evertrue/pricetag:$(date +%s)_$(git rev-parse --short HEAD) ./
```

## Running the Docker container

### First you need to run the Vault dev server in a separate terminal:

```
vault server -dev -dev-listen-address=$(ifconfig en0 | grep 'inet\b' | awk '{print $2}'):8200 -dev-root-token-id=FAKE_ROOT_TOKEN
```

### Load some data into the Vault dev server

```
VAULT_ADDR="http://$(ifconfig en0 | grep 'inet\b' | awk '{print $2}'):8200" VAULT_TOKEN=FAKE_ROOT_TOKEN vault-update -p secret/default/pricetag "{\"SENTRY_DSN\": \"FAKE_SENTRY_DSN\", \"MESOS_AGENT_INSTANCE_TYPE\": \"c3.4xlarge\", \"SINGULARITY_API\": \"http://stage-singularity.evertrue.com/api\"}"
```

### Finally, run the docker container

```
docker run -e RACK_ENV=deployment -e PASSENGER_APP_ENV=staging -e VAULT_TOKEN=FAKE_ROOT_TOKEN -e VAULT_ADDR="http://$(ifconfig en0 | grep 'inet\b' | awk '{print $2}'):8200" -p 8080:8080 registry.evertrue.com/evertrue/pricetag:$(docker images | grep pricetag | awk '{print $2}' | head -n 1)
```

You should now be able to access it using a URL like this:

```
http://localhost:8080/singularity.svg?request=stage-apache-zeppelin&env=stage
```

## Deployment

Use Dinghy:

```
BUILD_TAG=master-3 bundle exec dinghy deploy staging
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/evertrue/pricetag.

## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

