#!/usr/bin/env ruby
# frozen_string_literal: true

# Ruby script to fetch and display Freeplay prompt templates
# This demonstrates how to retrieve prompt template content from the Freeplay API
#
# Setup:
#   gem install dotenv
#   Copy .env.example to .env and fill in your values

require 'net/http'
require 'uri'
require 'json'
require 'dotenv/load' # Automatically loads .env file

# Configuration - loaded from .env file
FREEPLAY_API_KEY = ENV['FREEPLAY_API_KEY']
FREEPLAY_PROJECT_ID = ENV['FREEPLAY_PROJECT_ID']
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
    exit 1
  end
end

# Fetch a prompt template by name and environment
def fetch_prompt_template_by_name(name:, environment: 'latest', format: nil, flavor_name: nil)
  # Build query parameters
  query_params = {}
  query_params['environment'] = environment if environment
  query_params['format'] = format if format
  query_params['flavor_name'] = flavor_name if flavor_name
  
  query_string = query_params.empty? ? '' : "?#{URI.encode_www_form(query_params)}"
  
  # Properly encode the name (URI.encode_www_form_component works correctly)
  # But we need to ensure spaces become %20, not +
  encoded_name = URI.encode_www_form_component(name).gsub('+', '%20')
  
  uri = URI("#{FREEPLAY_API_URL}/projects/#{FREEPLAY_PROJECT_ID}/prompt-templates/name/#{encoded_name}#{query_string}")
  
  make_get_request(uri)
end

# List all prompt templates in the project
def list_prompt_templates
  uri = URI("#{FREEPLAY_API_URL}/projects/#{FREEPLAY_PROJECT_ID}/prompt-templates")
  
  make_get_request(uri)
end

# Generic HTTP GET helper
def make_get_request(uri)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = uri.scheme == 'https'

  request = Net::HTTP::Get.new(uri)
  request['Authorization'] = "Bearer #{FREEPLAY_API_KEY}"
  request['Content-Type'] = 'application/json'

  puts "\nSending GET request to: #{uri}"

  response = http.request(request)

  puts "Response status: #{response.code}"

  {
    status: response.code.to_i,
    body: response.body.empty? ? {} : JSON.parse(response.body)
  }
rescue StandardError => e
  puts "Error making request: #{e.message}"
  { status: 0, error: e.message }
end

# Display prompt template content in a readable format
def display_prompt_template(template)
  puts "\n" + "=" * 80
  puts "PROMPT TEMPLATE DETAILS"
  puts "=" * 80
  
  puts "\nBasic Information:"
  puts "  Name: #{template['prompt_template_name']}"
  puts "  Template ID: #{template['prompt_template_id']}"
  puts "  Version ID: #{template['prompt_template_version_id']}"
  puts "  Version Name: #{template['version_name'] || 'N/A'}"
  puts "  Version Description: #{template['version_description'] || 'N/A'}"
  puts "  Format Version: #{template['format_version']}"
  
  if template['metadata']
    puts "\nMetadata:"
    puts "  Provider: #{template['metadata']['provider'] || 'N/A'}"
    puts "  Model: #{template['metadata']['model'] || 'N/A'}"
    puts "  Flavor: #{template['metadata']['flavor'] || 'N/A'}"
    
    if template['metadata']['params'] && !template['metadata']['params'].empty?
      puts "  Parameters:"
      template['metadata']['params'].each do |key, value|
        puts "    #{key}: #{value}"
      end
    end
  end
  
  if template['content'] && !template['content'].empty?
    puts "\n" + "-" * 80
    puts "PROMPT CONTENT:"
    puts "-" * 80
    
    template['content'].each_with_index do |message, index|
      if message['kind'] == 'history'
        puts "\n[#{index + 1}] <<CONVERSATION HISTORY PLACEHOLDER>>"
      else
        puts "\n[#{index + 1}] Role: #{message['role'].upcase}"
        puts "Content:"
        puts message['content']
        
        if message['media_slots'] && !message['media_slots'].empty?
          puts "\nMedia Slots:"
          message['media_slots'].each do |slot|
            puts "  - Type: #{slot['type']}, Placeholder: {{#{slot['placeholder_name']}}}"
          end
        end
      end
    end
  end
  
  if template['tool_schema'] && !template['tool_schema'].empty?
    puts "\n" + "-" * 80
    puts "TOOL SCHEMA:"
    puts "-" * 80
    
    template['tool_schema'].each_with_index do |tool, index|
      puts "\n[#{index + 1}] Tool: #{tool['name']}"
      puts "Description: #{tool['description']}"
      puts "Parameters: #{JSON.pretty_generate(tool['parameters'])}"
    end
  end
  
  if template['output_schema']
    puts "\n" + "-" * 80
    puts "OUTPUT SCHEMA:"
    puts "-" * 80
    puts JSON.pretty_generate(template['output_schema'])
  end
  
  puts "\n" + "=" * 80
end

# Display a summary list of prompt templates
def display_prompt_list(response)
  puts "\n" + "=" * 80
  puts "AVAILABLE PROMPT TEMPLATES"
  puts "=" * 80
  
  templates = response['data'] || []
  
  if templates.empty?
    puts "\nNo prompt templates found in this project."
    return
  end
  
  templates.each_with_index do |template, index|
    puts "\n[#{index + 1}] #{template['name']}"
    puts "    ID: #{template['id']}"
    puts "    Latest Version ID: #{template['latest_template_version_id'] || 'N/A'}"
  end
  
  # Show pagination info
  if response['pagination']
    pagination = response['pagination']
    puts "\n" + "-" * 80
    puts "Page #{pagination['page']} (#{pagination['page_size']} per page)"
    puts "Has more pages: #{pagination['has_next']}"
  end
  
  puts "\n" + "=" * 80
end

# Main execution
def main
  validate_config!

  puts "=" * 80
  puts "Freeplay Prompt Template Fetcher"
  puts "=" * 80

  # Check command line arguments
  if ARGV.empty?
    puts "\nUsage:"
    puts "  ruby fetch_prompt_template.rb list                           # List all templates"
    puts "  ruby fetch_prompt_template.rb <prompt_name> [environment]    # Fetch specific template"
    puts "\nExamples:"
    puts "  ruby fetch_prompt_template.rb list"
    puts "  ruby fetch_prompt_template.rb 'my-prompt' latest"
    puts "  ruby fetch_prompt_template.rb 'my-prompt' production"
    exit 1
  end

  command = ARGV[0]

  if command == 'list'
    # List all prompt templates
    puts "\nFetching all prompt templates..."
    result = list_prompt_templates
    
    if result[:status] == 200
      display_prompt_list(result[:body])
    else
      puts "\nError fetching prompt templates:"
      puts "Status: #{result[:status]}"
      puts "Response: #{JSON.pretty_generate(result[:body])}"
      exit 1
    end
  else
    # Fetch specific prompt template
    prompt_name = command
    environment = ARGV[1] || 'latest'
    
    puts "\nFetching prompt template:"
    puts "  Name: #{prompt_name}"
    puts "  Environment: #{environment}"
    
    result = fetch_prompt_template_by_name(
      name: prompt_name,
      environment: environment
    )
    
    if result[:status] == 200
      display_prompt_template(result[:body])
      
      # Show how to use this in your code
      puts "\n" + "=" * 80
      puts "USAGE EXAMPLE:"
      puts "=" * 80
      puts "\nTo use this prompt template in your application:"
      puts "\n# Set the prompt version ID in your .env file:"
      puts "FREEPLAY_PROMPT_VERSION_ID='#{result[:body]['prompt_template_version_id']}'"
      puts "\n# Then include it when recording completions (see freeplay_trace_example.rb)"
    else
      puts "\nError fetching prompt template:"
      puts "Status: #{result[:status]}"
      puts "Response: #{JSON.pretty_generate(result[:body])}"
      exit 1
    end
  end
end

# Run the script
main
