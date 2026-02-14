#!/usr/bin/env ruby
# frozen_string_literal: true

# Simple script to fetch a Freeplay prompt template by name
require 'net/http'
require 'uri'
require 'json'
require 'dotenv/load'

FREEPLAY_API_KEY = ENV['FREEPLAY_API_KEY']
FREEPLAY_PROJECT_ID = ENV['FREEPLAY_PROJECT_ID']
FREEPLAY_API_URL = ENV.fetch('FREEPLAY_API_URL', 'https://app.freeplay.ai/api/v2')

# Prompt template name (using the ID you provided: 2e04d891-03c9-44ce-b01d-f4dcf306b8eb is the "greeting" template)
PROMPT_NAME = 'greeting'
ENVIRONMENT = 'latest'

# Fetch the prompt template
encoded_name = URI.encode_www_form_component(PROMPT_NAME).gsub('+', '%20')
uri = URI("#{FREEPLAY_API_URL}/projects/#{FREEPLAY_PROJECT_ID}/prompt-templates/name/#{encoded_name}?environment=#{ENVIRONMENT}")

http = Net::HTTP.new(uri.host, uri.port)
http.use_ssl = true

request = Net::HTTP::Get.new(uri)
request['Authorization'] = "Bearer #{FREEPLAY_API_KEY}"
request['Content-Type'] = 'application/json'

response = http.request(request)
template = JSON.parse(response.body)

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
