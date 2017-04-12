required_env_keys = %w(
  SINGULARITY_API
  SENTRY_DSN
  MESOS_AGENT_INSTANCE_TYPE
)

missing = required_env_keys.select { |key| ENV[key].nil? || ENV[key].empty? }
fail "Missing required ENV vars! #{missing.join ' '}" if missing.any?

class Pricetag < Sinatra::Application
  # get '/tag/repo/*' do
  #   full_repo_path = params[:splat].first.split '/'
  #   git_username = full_repo_path[0]
  #   repo_name = full_repo_path[1]

  #   "Hello #{git_username}/#{repo_name} ref: #{params['ref']}!"
  # end

  configure do
    Raven.configure do |config|
      config.environments = %w(production staging)
      config.current_environment = ENV['PASSENGER_APP_ENV'] || 'development'
    end
  end

  error do
    unless %w(staging production).include? ENV['PASSENGER_APP_ENV']
      return "ERROR: #{env['sinatra.error']}"
    end

    event_id = nil
    Raven.capture_exception(env['sinatra.error']) { |event| event_id = event.id }

    msg = 'There was an issue while processing the request.'
    msg += " <Please reference event ID: #{event_id}>" if event_id
    msg
  end

  get '/singularity.svg' do
    content_type 'image/svg+xml', charset: 'utf-8'

    @singularity_request_id = params['request']

    Unirest.get("https://img.shields.io/badge/price-$#{cost}/month-lightgray.svg").body
  end

  get '/status' do
    # For now this really just allows Mesos to verify that our app is up
    status 200

    body json(
      status: 200,
      env: ENV['PASSENGER_APP_ENV']
    )
  end

  private

  def cost
    flavor = config[:mesos_agent_instance_type]

    instances = singularity_request['request']['instances']
    cpus = singularity_resources['cpus']

    # TODO: Figure out what to do about memory
    # memory = singularity_resources['memoryMb']

    ((on_demand_rate(flavor) * cpus * instances) * 24 * 30.4).round 2
  end

  def on_demand_rate(flavor)
    ec2_pricing = Unirest.get('http://aws.amazon.com/ec2/pricing/pricing-on-demand-instances.json').body
    region_pricing = ec2_pricing['config']['regions'].find { |r| r['region'] == 'us-east-1' }

    sizes = region_pricing['instanceTypes'].find do |it|
      it['sizes'].map { |s| s['size'] }.include?(flavor)
    end

    value_columns = sizes['sizes'].find { |s| s['size'] == flavor }['valueColumns']
    value_columns.find { |c| c['name'] == 'linux' }['prices']['USD'].to_f
  end

  def singularity_resources
    singularity_active_deploy['resources']
  end

  def singularity_active_deploy
    singularity_request['activeDeploy'] ||
      fail("Request #{request_id} has no active deploy")
  end

  def singularity_request
    @singularity_request ||= begin
      response =
        Unirest.get("#{config[:singularity_api]}/requests/request/#{@singularity_request_id}")
      return response.body if response.code == 200
      fail "Bad Singularity response: #{response.inspect}"
    end
  end

  def config
    {
      singularity_api: ENV['SINGULARITY_API'],
      mesos_agent_instance_type: ENV['MESOS_AGENT_INSTANCE_TYPE']
    }
  end
end
