#!/usr/bin/env ruby
# frozen_string_literal: true

# Script to fetch a Freeplay prompt template and render it with variable substitution
require 'net/http'
require 'uri'
require 'json'
require 'mustache'
require 'dotenv/load'

FREEPLAY_API_KEY = ENV['FREEPLAY_API_KEY']
FREEPLAY_PROJECT_ID = ENV['FREEPLAY_PROJECT_ID']
FREEPLAY_API_URL = ENV.fetch('FREEPLAY_API_URL', 'https://app.freeplay.ai/api/v2')

# Prompt template ID and version ID
PROMPT_TEMPLATE_ID = 'b86efe35-83e8-4370-b508-9cdeea74717c'
PROMPT_VERSION_ID = 'b813c6fe-eae6-4492-86d7-95052873bbf4'

# Variables to substitute
VARIABLES = {
  'name' => 'Jairo',
  'language' => 'Spanish'
}

# Fetch prompt template by template ID and version ID
def fetch_prompt_by_ids(template_id, version_id)
  # Use the direct API endpoint: GET /api/v2/projects/{project_id}/prompt-templates/id/{template_id}/versions/{version_id}
  uri = URI("#{FREEPLAY_API_URL}/projects/#{FREEPLAY_PROJECT_ID}/prompt-templates/id/#{template_id}/versions/#{version_id}")
  
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true

  request = Net::HTTP::Get.new(uri)
  request['Authorization'] = "Bearer #{FREEPLAY_API_KEY}"
  request['Content-Type'] = 'application/json'

  response = http.request(request)
  
  if response.code.to_i != 200
    puts "\nError: Failed to fetch prompt template"
    puts "Status: #{response.code}"
    puts "Response: #{response.body}"
    return nil
  end
  
  template = JSON.parse(response.body)
  template
end

# Render prompt content with variable substitution
def render_prompt(template, variables)
  rendered_content = []
  
  template['content'].each do |message|
    if message['kind'] == 'history'
      rendered_content << { 'kind' => 'history' }
    else
      # Use Mustache to render the content
      rendered_text = Mustache.render(message['content'], variables)
      rendered_content << {
        'role' => message['role'],
        'content' => rendered_text
      }
    end
  end
  
  rendered_content
end

# Main execution
puts "=" * 80
puts "FETCHING PROMPT TEMPLATE"
puts "=" * 80
puts "\nTemplate ID: #{PROMPT_TEMPLATE_ID}"
puts "Version ID: #{PROMPT_VERSION_ID}"
puts "Variables: #{VARIABLES.inspect}"

template = fetch_prompt_by_ids(PROMPT_TEMPLATE_ID, PROMPT_VERSION_ID)

if template.nil?
  puts "\nError: Could not find prompt template"
  exit 1
end

puts "\n" + "=" * 80
puts "ORIGINAL PROMPT TEMPLATE"
puts "=" * 80
puts "\nTemplate Name: #{template['prompt_template_name']}"
puts "Model: #{template['metadata']['model']}"
puts "Provider: #{template['metadata']['provider']}"
puts "\n" + "-" * 80

template['content'].each do |message|
  if message['kind'] == 'history'
    puts "\n[HISTORY PLACEHOLDER]"
  else
    puts "\n[#{message['role'].upcase}]"
    puts message['content']
  end
end

# Render the prompt with variables
rendered = render_prompt(template, VARIABLES)

puts "\n" + "=" * 80
puts "RENDERED PROMPT (WITH SUBSTITUTED VARIABLES)"
puts "=" * 80

rendered.each do |message|
  if message['kind'] == 'history'
    puts "\n[HISTORY PLACEHOLDER]"
  else
    puts "\n[#{message['role'].upcase}]"
    puts message['content']
  end
end

puts "\n" + "=" * 80
