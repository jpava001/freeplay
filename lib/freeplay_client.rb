# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'
require 'dotenv/load'

# FreeplayClient module provides shared functionality for interacting with the Freeplay API
# across multiple Ruby scripts
module FreeplayClient
  # Configuration class manages API credentials and settings
  class Configuration
    attr_reader :api_key, :project_id, :api_url, :prompt_version_id

    def initialize
      @api_key = ENV['FREEPLAY_API_KEY']
      @project_id = ENV['FREEPLAY_PROJECT_ID']
      @prompt_version_id = ENV['FREEPLAY_PROMPT_VERSION_ID']
      @api_url = ENV.fetch('FREEPLAY_API_URL', 'https://app.freeplay.ai/api/v2')
    end

    def valid?(required: [:api_key, :project_id])
      required.all? { |key| !send(key).nil? && !send(key).empty? }
    end
  end

  # HTTPClient handles all HTTP requests to the Freeplay API
  class HTTPClient
    def initialize(api_key, verbose: false)
      @api_key = api_key
      @verbose = verbose
    end

    def get(uri)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'

      request = Net::HTTP::Get.new(uri)
      request['Authorization'] = "Bearer #{@api_key}"
      request['Content-Type'] = 'application/json'

      log_request(uri, 'GET') if @verbose

      response = http.request(request)
      
      log_response(response) if @verbose

      {
        status: response.code.to_i,
        body: response.body.empty? ? {} : JSON.parse(response.body)
      }
    rescue StandardError => e
      handle_error(e)
    end

    def post(uri, payload)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'

      request = Net::HTTP::Post.new(uri)
      request['Authorization'] = "Bearer #{@api_key}"
      request['Content-Type'] = 'application/json'
      request.body = payload.to_json

      log_request(uri, 'POST', payload) if @verbose

      response = http.request(request)

      log_response(response) if @verbose

      {
        status: response.code.to_i,
        body: response.body.empty? ? {} : JSON.parse(response.body)
      }
    rescue StandardError => e
      handle_error(e)
    end

    private

    def log_request(uri, method, payload = nil)
      puts "\nSending #{method} request to: #{uri}"
      puts "Payload: #{JSON.pretty_generate(payload)}" if payload
    end

    def log_response(response)
      puts "\nResponse status: #{response.code}"
      puts "Response body: #{response.body}"
    end

    def handle_error(error)
      puts "Error making request: #{error.message}" if @verbose
      { status: 0, error: error.message }
    end
  end

  # API class provides methods for interacting with Freeplay endpoints
  class API
    def initialize(config, http_client)
      @config = config
      @http_client = http_client
    end

    # Record a completion to Freeplay
    def record_completion(session_id:, messages:, inputs:, **options)
      uri = URI("#{@config.api_url}/projects/#{@config.project_id}/sessions/#{session_id}/completions")

      payload = {
        messages: messages,
        inputs: inputs
      }

      # Optional: prompt template info
      if options[:prompt_version_id] || (@config.prompt_version_id && !@config.prompt_version_id.empty?)
        payload[:prompt_info] = {
          prompt_template_version_id: options[:prompt_version_id] || @config.prompt_version_id,
          environment: options[:environment] || 'latest'
        }
      end

      # Optional: trace association
      payload[:trace_info] = { trace_id: options[:trace_id] } if options[:trace_id]

      # Optional: call metadata (timing, tokens, etc.)
      payload[:call_info] = options[:call_info] if options[:call_info]

      # Optional: session metadata
      if options[:metadata] && !options[:metadata].empty?
        payload[:session_info] = { custom_metadata: options[:metadata] }
      end

      @http_client.post(uri, payload)
    end

    # Record a trace to Freeplay
    def record_trace(session_id:, trace_id:, input:, output:, **options)
      uri = URI("#{@config.api_url}/projects/#{@config.project_id}/sessions/#{session_id}/traces/id/#{trace_id}")

      payload = {
        input: input,
        output: output
      }

      payload[:agent_name] = options[:agent_name] if options[:agent_name]
      payload[:custom_metadata] = options[:metadata] if options[:metadata] && !options[:metadata].empty?

      @http_client.post(uri, payload)
    end

    # Fetch a prompt template from Freeplay
    def fetch_prompt_template(template_id: nil, version_id: nil, name: nil, environment: 'latest')
      if template_id && version_id
        # Fetch by template ID and version ID
        uri = URI("#{@config.api_url}/projects/#{@config.project_id}/prompt-templates/id/#{template_id}/versions/#{version_id}")
      elsif name
        # Fetch by name
        encoded_name = URI.encode_www_form_component(name).gsub('+', '%20')
        uri = URI("#{@config.api_url}/projects/#{@config.project_id}/prompt-templates/name/#{encoded_name}?environment=#{environment}")
      else
        raise ArgumentError, 'Must provide either template_id + version_id, or name'
      end

      @http_client.get(uri)
    end

    # Render prompt messages with variable substitution (requires Mustache gem)
    def render_prompt_messages(template, variables)
      require 'mustache'
      
      rendered_messages = []
      
      template['content'].each do |message|
        next if message['kind'] == 'history' # Skip history placeholders
        
        # Use Mustache to render the content
        rendered_text = Mustache.render(message['content'], variables)
        rendered_messages << {
          'role' => message['role'],
          'content' => rendered_text
        }
      end
      
      rendered_messages
    end
  end

  # Utilities module provides helper functions
  module Utilities
    # Validate that required configuration is present
    def self.validate_config!(config, required: [:api_key, :project_id])
      missing = required.reject { |key| val = config.send(key); val && !val.empty? }

      return if missing.empty?

      puts "Error: Missing required environment variables: #{missing.map { |k| "FREEPLAY_#{k.to_s.upcase}" }.join(', ')}"
      puts "\nPlease set them before running:"
      missing.each do |key|
        puts "  export FREEPLAY_#{key.to_s.upcase}='your-#{key.to_s.gsub('_', '-')}'"
      end
      exit 1
    end

    # Simple token estimation (roughly 4 characters per token)
    def self.estimate_tokens(text)
      (text.length / 4.0).ceil
    end
  end

  # Factory method to create a configured API client
  def self.create_client(verbose: false)
    config = Configuration.new
    http_client = HTTPClient.new(config.api_key, verbose: verbose)
    API.new(config, http_client)
  end

  # Get configuration instance
  def self.configuration
    Configuration.new
  end
end
