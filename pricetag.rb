required_env_keys = %w(
  SINGULARITY_API
  SENTRY_DSN
  MESOS_AGENT_INSTANCE_TYPE
)

missing = required_env_keys.select { |key| ENV[key].nil? || ENV[key].empty? }
fail "Missing required ENV vars! #{missing.join ' '}" if missing.any?

class Pricetag < Sinatra::Application
  EC2_RATE_TYPE = :reserved
  # EC2_RATE_TYPE = :on_demand

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
    logger.info 'First hint of a request'

    content_type 'image/svg+xml', charset: 'utf-8'

    @singularity_request_id = params['request']
    @region = params['region'] || 'us-east-1'

    logger.info "Request ID: #{@singularity_request_id} (region: #{@region})"

    # Unirest.get("https://img.shields.io/badge/price-$#{cost}/month-lightgray.svg").body
    img = Svgshield.new('price', "$#{format_cost}/month", 'lightgray').to_s
    logger.info 'Finished processing request'
    img
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

  def format_cost
    return cost if cost < 100.0
    return cost.round 0 if cost < 1000.0
    (cost / 1000.0).round(2).to_s + 'K'
  end

  def cost
    @cost ||= begin
      flavor = config[:mesos_agent_instance_type]

      # For some reason some requests just don't have an instances count O.o
      instances = singularity_request['request']['instances'] || 1
      requested_cpus = singularity_resources['cpus']

      # TODO: Figure out what to do about memory
      # memory = singularity_resources['memoryMb']

      c = (requested_cpus / total_cpus * rate(flavor) * instances * 24 * 30.4).round 2

      logger.info "Requested CPUs: #{requested_cpus}"
      logger.info "Total CPUs: #{total_cpus}"
      logger.info "#{config[:ec2_rate_type]} rate (for #{flavor}): #{discovered_rate}"
      logger.info "Instances: #{instances}"

      logger.info "Computed cost: #{c}"
      c
    end
  end

  def rate(flavor)
    return reserved_rate(flavor) if config[:ec2_rate_type] == :reserved
    on_demand_rate flavor
  end

  def reserved_rate(flavor)
    terms = region_pricing['instanceTypes'].find { |it| it['type'] == flavor }['terms']
    purchase_options =
      terms.find { |term| term['term'] == config[:reservation_term] }['purchaseOptions']
    value_columns =
      purchase_options.find { |po| po['purchaseOption'] == config[:reservation_po] }['valueColumns']
    r = value_columns.find { |col| col['name'] == 'effectiveHourly' }['prices']['USD'].to_f
    logger.info "Discovered reserved rate: #{r}"
    r
  end

  def on_demand_rate(flavor)
    sizes = region_pricing['instanceTypes'].map { |it| it['sizes'] }.flatten
    value_columns = sizes.find { |s| s['size'] == flavor }['valueColumns']
    r = value_columns.find { |col| col['name'] == 'linux' }['prices']['USD'].to_f
    logger.info "Discovered on-demand rate: #{r}"
    r
  end

  def region_pricing
    ec2_pricing['config']['regions'].find { |r| r['region'] == @region }
  end

  def ec2_pricing
    # Don't read this code. It will make your eyes bleed.
    # But seriously. This reads the pricing from AWS, which is actually in JS, strips off the
    # function call code, uses a regex to convert it to JSON, then parses it.
    #
    # If it breaks...I'm not surprised.

    logger.info 'Fetching pricing from AWS'

    pricing_js =
      if config[:ec2_rate_type] == :reserved
        Unirest.get('https://a0.awsstatic.com/pricing/1/ec2/ri-v2/linux-unix-shared.min.js').body
      else
        Unirest.get('https://a0.awsstatic.com/pricing/1/ec2/linux-od.min.js').body
      end

    logger.info 'Done fetching pricing'

    r = JSON.parse pricing_js.split('callback(')[1].sub(');', '').gsub(/(\w+):/, '"\1":')
    logger.info 'Done parsing pricing'
    r
  end

  def singularity_resources
    singularity_active_deploy['resources']
  end

  def singularity_active_deploy
    singularity_request['activeDeploy'] ||
      fail("Request #{request_id} has no active deploy")
  end

  def singularity_active_tasks
    logger.info 'Fetching active tasks from Singularity'
    response =
      Unirest.get(
        "#{config[:singularity_api]}/history/request/#{@singularity_request_id}/tasks/active"
      )
    logger.info 'Done fetching active tasks from Singularity'
    fail "Bad Singularity response: #{response.inspect}" if response.code != 200
    return response.body if response.body.any?
    fail "The request #{@singularity_request_id} has no active tasks"
  end

  def total_cpus
    # Sum up the total available CPUs on all agents where the task is currently running

    request_mesos_agents.inject(0) { |a, e| a + e['resources']['cpus'] }
  end

  def request_mesos_agents
    request_hostnames = singularity_active_tasks.map do |task|
      task['taskId']['sanitizedHost'].tr '_', '-'
    end
    all_mesos_agents.select { |agent| request_hostnames.include? agent['host'] }
  end

  def all_mesos_agents
    @all_mesos_agents ||= Unirest.get("#{config[:singularity_api]}/slaves").body
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
      mesos_agent_instance_type: ENV['MESOS_AGENT_INSTANCE_TYPE'],
      ec2_rate_type: EC2_RATE_TYPE,
      reservation_term: 'yrTerm1Standard',
      reservation_po: 'partialUpfront'
    }
  end
end
