require 'httparty'
require 'oauth2'

class NetsuiteService
  include HTTParty

  def initialize(auth_type: :oauth2)
    @auth_type = auth_type
    @base_url = "#{ENV['NETSUITE_BASE_URL']}/services/rest/record/v1/salesOrder"
    @headers = { 'Content-Type' => 'application/json' }
  end

  # Fetches a Sales Order record by order ID
  def get_sales_order(order_id)
    case @auth_type
    when :oauth2
      access_token = oauth2_access_token
      auth_headers = { 'Authorization' => "Bearer #{access_token}" }
    when :oauth1
      auth_headers = oauth1_auth_headers("GET", "#{@base_url}/#{order_id}")
    when :tba
      auth_headers = tba_auth_headers
    else
      raise "Invalid authentication type: #{@auth_type}"
    end


    Rails.logger.info("[Requesting Sales Order Path:] #{@base_url}/#{order_id}")
    Rails.logger.info("[Requesting Sales Order with headers:] #{JSON.pretty_generate(auth_headers.merge(@headers))}")

    response = self.class.get("#{@base_url}/#{order_id}", headers: @headers.merge(auth_headers))

    log_response(response)
    Log.create!(message: "Status for order  #{JSON(response.body)['orderStatus']}")

    handle_response(response)
  rescue StandardError => e
    log_error(e.message)
    { error: e.message }
  end

  private

  # Retrieves OAuth 2.0 Access Token
  def oauth2_access_token
    client = OAuth2::Client.new(
      ENV['OAUTH_CLIENT_ID'],
      ENV['OAUTH_CLIENT_SECRET'],
      site: ENV['NETSUITE_BASE_URL']
    )
    token = client.client_credentials.get_token
    token.token
  end

  # Constructs Token-Based Authentication headers
  def tba_auth_headers
    account_id = ENV['TBA_ACCOUNT_ID']
    email = ENV['TBA_EMAIL']
    signature = "#{ENV['TBA_TOKEN_ID']}&#{ENV['TBA_TOKEN_SECRET']}"
    {
      'Authorization' => "NLAuth nlauth_account=#{account_id}, nlauth_email=#{email}, nlauth_signature=#{signature}"
    }
  end

  # OAuth 1.0 Authorization Header
  def oauth1_auth_headers(http_method, url)
    consumer_key = ENV['OAUTH1_CONSUMER_KEY']
    consumer_secret = ENV['OAUTH1_CONSUMER_SECRET']
    token = ENV['OAUTH1_TOKEN']
    token_secret = ENV['OAUTH1_TOKEN_SECRET']
    realm = ENV['NETSUITE_REALM']
    nonce = SecureRandom.hex
    timestamp = Time.now.to_i.to_s

    # Extract query parameters from URL
    uri = URI.parse(url)
    query_params = URI.decode_www_form(uri.query || '').to_h

    # OAuth parameters
    oauth_params = {
      'oauth_consumer_key' => consumer_key,
      'oauth_token' => token,
      'oauth_nonce' => nonce,
      'oauth_timestamp' => timestamp,
      'oauth_signature_method' => 'HMAC-SHA256', # Updated to HMAC-SHA256
      'oauth_version' => '1.0'
    }

    # Merge OAuth and query parameters for signature
    all_params = oauth_params.merge(query_params)
    base_string = signature_base_string(http_method, url, all_params)
    signing_key = "#{CGI.escape(consumer_secret)}&#{CGI.escape(token_secret)}"
    signature = Base64.strict_encode64(OpenSSL::HMAC.digest('sha256', signing_key, base_string)) # Use SHA256

    # Add signature to OAuth parameters
    oauth_params['oauth_signature'] = signature

    # Build the Authorization header
    auth_header = oauth_params.map { |k, v| "#{k}=\"#{CGI.escape(v)}\"" }.join(', ')
    { 'Authorization' => "OAuth realm=\"#{realm}\", #{auth_header}" } # Include realm
  end

  # Generates the OAuth 1.0 signature base string
  def signature_base_string(http_method, url, params)
    encoded_params = params.sort.map { |k, v| "#{CGI.escape(k)}=#{CGI.escape(v)}" }.join('&')
    "#{http_method.upcase}&#{CGI.escape(url)}&#{CGI.escape(encoded_params)}"
  end

  def log_debug(message)
    Rails.logger.debug("[DEBUG] #{message}")
  end

  def log_request(request)
    Rails.logger.info("[REQUEST] #{JSON.pretty_generate(JSON.parse(request))}")
  end

  # Logs successful responses
  def log_response(response)

    Rails.logger.info("[RESPONSE] Status: #{response.code}, \n Body: #{JSON.pretty_generate(JSON.parse(response.body))}")
    Log.create!(message: "Response: #{response.body}")
  end

  # Logs errors
  def log_error(message)
    Rails.logger.error("[ERROR] #{message}")
    Log.create!(message: "Error: #{message}")
  end

  # Handles HTTP response
  def handle_response(response)
    if response.success?
      JSON.parse(response.body)
    else
      { error: "Failed with status #{response.code}: #{response.body}" }
    end
  end
end