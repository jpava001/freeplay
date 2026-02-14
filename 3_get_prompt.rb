#!/usr/bin/env ruby
# frozen_string_literal: true

# Simple script to fetch a Freeplay prompt template by name
require_relative 'lib/freeplay_client'

# Prompt template name (using the ID you provided: 2e04d891-03c9-44ce-b01d-f4dcf306b8eb is the "greeting" template)
PROMPT_NAME = 'greeting'
ENVIRONMENT = 'latest'

# Initialize Freeplay client
config = FreeplayClient.configuration
FreeplayClient::Utilities.validate_config!(config)

client = FreeplayClient.create_client

# Fetch the prompt template
result = client.fetch_prompt_template(name: PROMPT_NAME, environment: ENVIRONMENT)

if result[:status] != 200
  puts "Error: Failed to fetch prompt template (Status: #{result[:status]})"
  puts "Response: #{result[:body]}"
  exit 1
end

template = result[:body]

# Display the prompt
puts "=" * 80
puts "PROMPT TEMPLATE: #{template['prompt_template_name']}"
puts "=" * 80
puts "\nTemplate ID: #{template['prompt_template_id']}"
puts "Version ID: #{template['prompt_template_version_id']}"
puts "Model: #{template['metadata']['model']}"
puts "Provider: #{template['metadata']['provider']}"
puts "\n" + "-" * 80
puts "PROMPT CONTENT:"
puts "-" * 80

template['content'].each do |message|
  if message['kind'] == 'history'
    puts "\n[HISTORY PLACEHOLDER]"
  else
    puts "\n[#{message['role'].upcase}]"
    puts message['content']
  end
end

puts "\n" + "=" * 80
