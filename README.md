# Pricetag

![Price Tag](https://img.shields.io/badge/price-25.33%2Fhr-lightgray.svg "Price Tag")

A tiny web server that serves up SVG shield price tags for your Mesos apps. The number is based on CPUs requested in the Singularity `request` object.

## Usage

Build it into a docker container.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/evertrue/pricetag.

## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

