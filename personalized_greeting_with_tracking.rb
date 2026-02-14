#!/usr/bin/env ruby
# frozen_string_literal: true

# Script that:
# 1. Fetches a prompt template from Freeplay
# 2. Renders it with variable substitution
# 3. Simulates an LLM response
# 4. Records both completion and trace to Freeplay for tracking

require 'net/http'
require 'uri'
require 'json'
require 'mustache'
require 'securerandom'
require 'dotenv/load'

# Configuration
FREEPLAY_API_KEY = ENV['FREEPLAY_API_KEY']
FREEPLAY_PROJECT_ID = ENV['FREEPLAY_PROJECT_ID']
FREEPLAY_API_URL = ENV.fetch('FREEPLAY_API_URL', 'https://app.freeplay.ai/api/v2')

# Prompt template configuration
PROMPT_TEMPLATE_ID = 'b86efe35-83e8-4370-b508-9cdeea74717c'
PROMPT_VERSION_ID = 'b813c6fe-eae6-4492-86d7-95052873bbf4'

# Variables to substitute in the prompt
VARIABLES = {
  'name' => 'Jairo',
  'language' => 'Spanish'
}

# Fetch prompt template by template ID and version ID
def fetch_prompt_template(template_id, version_id)
  uri = URI("#{FREEPLAY_API_URL}/projects/#{FREEPLAY_PROJECT_ID}/prompt-templates/id/#{template_id}/versions/#{version_id}")
  
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true

  request = Net::HTTP::Get.new(uri)
  request['Authorization'] = "Bearer #{FREEPLAY_API_KEY}"
  request['Content-Type'] = 'application/json'

  response = http.request(request)
  
  if response.code.to_i != 200
    puts "Error: Failed to fetch prompt template (Status: #{response.code})"
    return nil
  end
  
  JSON.parse(response.body)
end

# Render prompt content with variable substitution
def render_prompt_messages(template, variables)
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

# Simulate an LLM response based on the prompt
def simulate_llm_response(rendered_messages, variables)
  # In reality, this would call an actual LLM API
  # For now, we'll simulate a Spanish greeting based on the inputs
  
  name = variables['name']
  language = variables['language']
  
  # Simulated response - a greeting in Spanish
  assistant_response = "¡Hola #{name}! ¿Cómo estás? Es un placer saludarte en #{language}."
  
  {
    response: assistant_response,
    model: 'claude-sonnet-4.5',
    provider: 'anthropic',
    input_tokens: 35,
    output_tokens: 25
  }
end

# Record a completion to Freeplay
def record_completion(session_id:, messages:, inputs:, call_info:, trace_id:, prompt_version_id:)
  uri = URI("#{FREEPLAY_API_URL}/projects/#{FREEPLAY_PROJECT_ID}/sessions/#{session_id}/completions")

  payload = {
    messages: messages,
    inputs: inputs,
    call_info: call_info,
    trace_info: { trace_id: trace_id },
    prompt_info: {
      prompt_template_version_id: prompt_version_id,
      environment: 'latest'
    }
  }

  make_post_request(uri, payload)
end

# Record a trace to Freeplay
def record_trace(session_id:, trace_id:, input:, output:, agent_name:)
  uri = URI("#{FREEPLAY_API_URL}/projects/#{FREEPLAY_PROJECT_ID}/sessions/#{session_id}/traces/id/#{trace_id}")

  payload = {
    input: input,
    output: output,
    agent_name: agent_name
  }

  make_post_request(uri, payload)
end

# Generic HTTP POST helper
def make_post_request(uri, payload)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = uri.scheme == 'https'

  request = Net::HTTP::Post.new(uri)
  request['Authorization'] = "Bearer #{FREEPLAY_API_KEY}"
  request['Content-Type'] = 'application/json'
  request.body = payload.to_json

  response = http.request(request)

  {
    status: response.code.to_i,
    body: response.body.empty? ? {} : JSON.parse(response.body)
  }
rescue StandardError => e
  puts "Error: #{e.message}"
  { status: 0, error: e.message }
end

# Main execution
def main
  puts "=" * 80
  puts "Personalized Greeting with Freeplay Tracking"
  puts "=" * 80
  
  # Generate unique IDs for this session and trace
  session_id = SecureRandom.uuid
  trace_id = SecureRandom.uuid
  
  puts "\nSession ID: #{session_id}"
  puts "Trace ID: #{trace_id}"
  puts "Variables: #{VARIABLES.inspect}"
  
  # Step 1: Fetch the prompt template
  puts "\n" + "-" * 80
  puts "Step 1: Fetching prompt template..."
  puts "-" * 80
  
  template = fetch_prompt_template(PROMPT_TEMPLATE_ID, PROMPT_VERSION_ID)
  
  if template.nil?
    puts "Failed to fetch prompt template. Exiting."
    exit 1
  end
  
  puts "✓ Fetched template: #{template['prompt_template_name']}"
  puts "  Model: #{template['metadata']['model']}"
  puts "  Provider: #{template['metadata']['provider']}"
  
  # Step 2: Render the prompt with variables
  puts "\n" + "-" * 80
  puts "Step 2: Rendering prompt with variables..."
  puts "-" * 80
  
  rendered_messages = render_prompt_messages(template, VARIABLES)
  
  puts "✓ Rendered prompt:"
  rendered_messages.each do |msg|
    puts "\n[#{msg['role'].upcase}]"
    puts msg['content']
  end
  
  # Step 3: Simulate LLM response
  puts "\n" + "-" * 80
  puts "Step 3: Simulating LLM response..."
  puts "-" * 80
  
  llm_result = simulate_llm_response(rendered_messages, VARIABLES)
  
  puts "✓ Simulated response:"
  puts llm_result[:response]
  
  # Step 4: Build complete messages array (prompt + response)
  complete_messages = rendered_messages + [
    { 'role' => 'assistant', 'content' => llm_result[:response] }
  ]
  
  # Step 5: Record completion to Freeplay
  puts "\n" + "-" * 80
  puts "Step 4: Recording completion to Freeplay..."
  puts "-" * 80
  
  call_info = {
    model: llm_result[:model],
    provider: llm_result[:provider],
    start_time: (Time.now - 1).to_f,
    end_time: Time.now.to_f,
    usage: {
      prompt_tokens: llm_result[:input_tokens],
      completion_tokens: llm_result[:output_tokens]
    }
  }
  
  completion_result = record_completion(
    session_id: session_id,
    messages: complete_messages,
    inputs: VARIABLES,
    call_info: call_info,
    trace_id: trace_id,
    prompt_version_id: PROMPT_VERSION_ID
  )
  
  if completion_result[:status].between?(200, 299)
    puts "✓ Completion recorded successfully"
    puts "  Completion ID: #{completion_result[:body]['completion_id']}" if completion_result[:body]['completion_id']
  else
    puts "✗ Failed to record completion (Status: #{completion_result[:status]})"
    puts "  Response: #{completion_result[:body]}"
  end
  
  # Step 6: Record trace to Freeplay
  puts "\n" + "-" * 80
  puts "Step 5: Recording trace to Freeplay..."
  puts "-" * 80
  
  # Build input summary
  input_summary = "Generate greeting for #{VARIABLES['name']} in #{VARIABLES['language']}"
  
  trace_result = record_trace(
    session_id: session_id,
    trace_id: trace_id,
    input: input_summary,
    output: llm_result[:response],
    agent_name: 'personalized-greeting-agent'
  )
  
  if trace_result[:status].between?(200, 299)
    puts "✓ Trace recorded successfully"
  else
    puts "✗ Failed to record trace (Status: #{trace_result[:status]})"
    puts "  Response: #{trace_result[:body]}"
  end
  
  # Summary
  puts "\n" + "=" * 80
  puts "Summary"
  puts "=" * 80
  puts "Completion: #{completion_result[:status].between?(200, 299) ? '✓ Success' : '✗ Failed'}"
  puts "Trace: #{trace_result[:status].between?(200, 299) ? '✓ Success' : '✗ Failed'}"
  puts "\nView your interaction at: https://app.freeplay.ai"
  puts "Session ID: #{session_id}"
  puts "=" * 80
end

# Run the script
main
