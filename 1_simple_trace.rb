#!/usr/bin/env ruby
# frozen_string_literal: true

# Simple Ruby script to send traces to Freeplay
# This simulates an LLM interaction and records it via the Freeplay HTTP API
#
# Setup:
#   gem install dotenv
#   Copy .env.example to .env and fill in your values

require 'net/http'
require 'uri'
require 'json'
require 'securerandom'
require 'dotenv/load' # Automatically loads .env file

# Configuration - loaded from .env file
FREEPLAY_API_KEY = ENV['FREEPLAY_API_KEY']
FREEPLAY_PROJECT_ID = ENV['FREEPLAY_PROJECT_ID']
FREEPLAY_PROMPT_VERSION_ID = ENV['FREEPLAY_PROMPT_VERSION_ID'] # Optional: your prompt template version ID
FREEPLAY_API_URL = ENV.fetch('FREEPLAY_API_URL', 'https://app.freeplay.ai/api/v2')

def validate_config!
  missing = []
  missing << 'FREEPLAY_API_KEY' unless FREEPLAY_API_KEY
  missing << 'FREEPLAY_PROJECT_ID' unless FREEPLAY_PROJECT_ID

  unless missing.empty?
    puts "Error: Missing required environment variables: #{missing.join(', ')}"
    puts "\nPlease set them before running:"
    puts "  export FREEPLAY_API_KEY='your-api-key'"
    puts "  export FREEPLAY_PROJECT_ID='your-project-id'"
    puts "  export FREEPLAY_PROMPT_VERSION_ID='your-prompt-version-id' # Optional"
    exit 1
  end
end

# Simulate an LLM interaction (no actual API call)
def simulate_llm_call(user_message)
  puts "Simulating LLM call..."
  puts "  User: #{user_message}"

  # Simulated response - in reality this would come from OpenAI, Anthropic, etc.
  assistant_response = "Hi, how are you?"

  puts "  Assistant: #{assistant_response}"

  {
    user_message: user_message,
    assistant_response: assistant_response,
    model: 'gpt-4o',
    provider: 'openai',
    input_tokens: 5,
    output_tokens: 6
  }
end

# Record a completion to Freeplay
def record_completion(session_id:, messages:, inputs:, call_info: nil, trace_id: nil)
  uri = URI("#{FREEPLAY_API_URL}/projects/#{FREEPLAY_PROJECT_ID}/sessions/#{session_id}/completions")

  payload = {
    messages: messages,
    inputs: inputs
  }

  # Only include prompt_info if we have a prompt template version ID
  # If you don't use Freeplay prompt templates, you can omit this entirely
  if FREEPLAY_PROMPT_VERSION_ID && !FREEPLAY_PROMPT_VERSION_ID.empty?
    payload[:prompt_info] = {
      prompt_template_version_id: FREEPLAY_PROMPT_VERSION_ID,
      environment: 'latest'
    }
  end

  # Add trace association if provided
  payload[:trace_info] = { trace_id: trace_id } if trace_id

  # Add call metadata if provided (timing, tokens, etc.)
  payload[:call_info] = call_info if call_info

  make_request(uri, payload)
end

# Record a trace to Freeplay (groups multiple completions together)
def record_trace(session_id:, trace_id:, input:, output:, agent_name: nil)
  uri = URI("#{FREEPLAY_API_URL}/projects/#{FREEPLAY_PROJECT_ID}/sessions/#{session_id}/traces/id/#{trace_id}")

  payload = {
    input: input,
    output: output
  }

  payload[:agent_name] = agent_name if agent_name

  make_request(uri, payload)
end

# Generic HTTP POST helper
def make_request(uri, payload)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = uri.scheme == 'https'

  request = Net::HTTP::Post.new(uri)
  request['Authorization'] = "Bearer #{FREEPLAY_API_KEY}"
  request['Content-Type'] = 'application/json'
  request.body = payload.to_json

  puts "\nSending request to: #{uri}"
  puts "Payload: #{JSON.pretty_generate(payload)}"

  response = http.request(request)

  puts "\nResponse status: #{response.code}"
  puts "Response body: #{response.body}"

  {
    status: response.code.to_i,
    body: response.body.empty? ? {} : JSON.parse(response.body)
  }
rescue StandardError => e
  puts "Error making request: #{e.message}"
  { status: 0, error: e.message }
end

# Main execution
def main
  validate_config!

  puts "=" * 60
  puts "Freeplay Trace Example - Ruby"
  puts "=" * 60

  # Generate unique IDs for this session and trace
  session_id = SecureRandom.uuid
  trace_id = SecureRandom.uuid

  puts "\nSession ID: #{session_id}"
  puts "Trace ID: #{trace_id}"
  puts

  # Step 1: Simulate the LLM interaction
  user_message = "Hello world!"
  llm_result = simulate_llm_call(user_message)

  # Step 2: Build the messages array (what was sent to and received from the LLM)
  messages = [
    { role: 'user', content: llm_result[:user_message] },
    { role: 'assistant', content: llm_result[:assistant_response] }
  ]

  # Step 3: Record the completion to Freeplay
  puts "\n" + "=" * 60
  puts "Recording completion to Freeplay..."
  puts "=" * 60

  call_info = {
    model: llm_result[:model],
    provider: llm_result[:provider],
    start_time: (Time.now - 1).to_f, # Unix timestamp (simulate 1 second ago)
    end_time: Time.now.to_f,         # Unix timestamp
    usage: {
      prompt_tokens: llm_result[:input_tokens],
      completion_tokens: llm_result[:output_tokens]
    }
  }

  completion_result = record_completion(
    session_id: session_id,
    messages: messages,
    inputs: { prompt: user_message }, # The variables used in your prompt template
    call_info: call_info,
    trace_id: trace_id
  )

  # Step 4: Record the trace (optional - useful for grouping multiple completions)
  puts "\n" + "=" * 60
  puts "Recording trace to Freeplay..."
  puts "=" * 60

  trace_result = record_trace(
    session_id: session_id,
    trace_id: trace_id,
    input: user_message,
    output: llm_result[:assistant_response],
    agent_name: 'hello-world-agent'
  )

  # Summary
  puts "\n" + "=" * 60
  puts "Summary"
  puts "=" * 60
  puts "Completion recorded: #{completion_result[:status].between?(200, 299) ? 'Success' : 'Failed'} (status: #{completion_result[:status]})"
  puts "Trace recorded: #{trace_result[:status].between?(200, 299) ? 'Success' : 'Failed'} (status: #{trace_result[:status]})"
  puts "\nView your traces at: https://app.freeplay.ai"
end

# Run the script
main
