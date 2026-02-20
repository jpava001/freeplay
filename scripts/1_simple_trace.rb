#!/usr/bin/env ruby
# frozen_string_literal: true

# Simple Ruby script to send traces to Freeplay
# This simulates an LLM interaction and records it via the Freeplay HTTP API
#
# Setup:
#   gem install dotenv
#   Copy .env.example to .env and fill in your values

require 'securerandom'
require_relative 'lib/freeplay_client'

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

# Main execution
def main
  # Initialize Freeplay client with verbose logging
  config = FreeplayClient.configuration
  FreeplayClient::Utilities.validate_config!(config)
  
  client = FreeplayClient.create_client(verbose: true)

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

  completion_result = client.record_completion(
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

  trace_result = client.record_trace(
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
