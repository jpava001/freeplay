#!/usr/bin/env ruby
# frozen_string_literal: true

# Script that:
# 1. Fetches a prompt template from Freeplay
# 2. Renders it with variable substitution
# 3. Simulates an LLM response
# 4. Records both completion and trace to Freeplay for tracking

require 'securerandom'
require_relative 'lib/freeplay_client'

# Prompt template configuration
PROMPT_TEMPLATE_ID = 'b86efe35-83e8-4370-b508-9cdeea74717c'
PROMPT_VERSION_ID = 'b813c6fe-eae6-4492-86d7-95052873bbf4'

# Variables to substitute in the prompt
VARIABLES = {
  'name' => 'Jairo',
  'language' => 'Spanish'
}


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

# Main execution
def main
  # Initialize Freeplay client
  config = FreeplayClient.configuration
  FreeplayClient::Utilities.validate_config!(config)
  
  client = FreeplayClient.create_client

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
  
  result = client.fetch_prompt_template(template_id: PROMPT_TEMPLATE_ID, version_id: PROMPT_VERSION_ID)
  
  if result[:status] != 200
    puts "Failed to fetch prompt template. Exiting."
    puts "Error: #{result[:body]}"
    exit 1
  end
  
  template = result[:body]
  
  puts "✓ Fetched template: #{template['prompt_template_name']}"
  puts "  Model: #{template['metadata']['model']}"
  puts "  Provider: #{template['metadata']['provider']}"
  
  # Step 2: Render the prompt with variables
  puts "\n" + "-" * 80
  puts "Step 2: Rendering prompt with variables..."
  puts "-" * 80
  
  rendered_messages = client.render_prompt_messages(template, VARIABLES)
  
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
  
  completion_result = client.record_completion(
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
  
  trace_result = client.record_trace(
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
