#!/usr/bin/env ruby
# frozen_string_literal: true

# Ruby script to process reading comprehension test cases with Freeplay prompt templates
# This fetches a prompt template, replaces variables with test data, and submits traces
#
# Setup:
#   gem install dotenv
#   Copy .env.example to .env and fill in your values

require 'securerandom'
require_relative 'lib/freeplay_client'

# Path to test cases
TEST_CASES_FILE = File.join(__dir__, 'data', 'assignment_evaluation_test_cases.json')

# Prompt template configuration
PROMPT_TEMPLATE_ID = 'c1441bc9-2797-4c6a-8b4e-456212e41d8c'
PROMPT_VERSION_ID = 'd2a36542-a917-4c6a-a987-478883aab956'

def validate_test_file!
  unless File.exist?(TEST_CASES_FILE)
    puts "Error: Test cases file not found at #{TEST_CASES_FILE}"
    exit 1
  end
end

def validate_prompt_config!
  if PROMPT_TEMPLATE_ID == 'YOUR_TEMPLATE_ID_HERE'
    puts "Error: Please update PROMPT_TEMPLATE_ID in the script with your template ID"
    puts "Current PROMPT_VERSION_ID: #{PROMPT_VERSION_ID}"
    exit 1
  end
end

# Fetch the prompt template from Freeplay (call once)
def fetch_prompt_template(client)
  result = client.fetch_prompt_template(
    template_id: PROMPT_TEMPLATE_ID,
    version_id: PROMPT_VERSION_ID
  )

  if result[:status] != 200
    puts "✗ Failed to fetch prompt template (status: #{result[:status]})"
    puts "  Response: #{result[:body]}"
    return nil
  end

  result[:body]
end

# Render the prompt template with variables from test case
def render_prompt(client, template, test_case)
  # Build variables from test case
  # Map test_case keys to prompt template variable names
  variables = {
    'student_grade' => test_case['student_grade'].to_s,
    'passage' => test_case['passage'],
    'question' => test_case['question'],
    'rubric' => test_case['rubric'],
    'student_answer' => test_case['student_answer']
  }

  # Render the prompt with variables
  rendered_messages = client.render_prompt_messages(template, variables)

  {
    rendered_messages: rendered_messages,
    variables: variables
  }
end

# Simulate LLM grading (using test case data)
def simulate_llm_grading(rendered_messages, test_case)
  # In a real scenario, you would call an LLM API here
  # For this simulation, we use the llm_scoring_output from the test case
  scoring_output = test_case['llm_scoring_output']

  # Format the response as if it came from an LLM
  response_text = format_scoring_response(scoring_output)

  {
    response: response_text,
    scoring_output: scoring_output,
    model: 'gpt-4o',
    provider: 'openai',
    input_tokens: estimate_tokens_from_messages(rendered_messages),
    output_tokens: FreeplayClient::Utilities.estimate_tokens(response_text)
  }
end

# Estimate tokens from rendered messages
def estimate_tokens_from_messages(messages)
  total = 0
  messages.each do |msg|
    total += FreeplayClient::Utilities.estimate_tokens(msg['content'] || '')
  end
  total
end

# Format the scoring output as a readable response
def format_scoring_response(scoring_output)
  response = "**Scoring Results:**\n\n"

  # Add criterion scores
  criterion_num = 1
  while scoring_output.key?("criterion_#{criterion_num}_score")
    score = scoring_output["criterion_#{criterion_num}_score"]
    reasoning = scoring_output["criterion_#{criterion_num}_reasoning"]
    response += "**Criterion #{criterion_num}:** #{score}/2\n"
    response += "#{reasoning}\n\n"
    criterion_num += 1
  end

  response += "**Total Score:** #{scoring_output['total_score']}\n\n"
  response += "**Overall Feedback:**\n#{scoring_output['overall_feedback']}"

  response
end

# Process a single test case
def process_test_case(client, template, test_case, index, total)
  puts "\n" + "=" * 80
  puts "Processing test case #{index + 1}/#{total}: #{test_case['id']}"
  puts "=" * 80

  # Generate unique IDs for this interaction
  session_id = SecureRandom.uuid
  trace_id = SecureRandom.uuid

  # Render the prompt template with test case variables
  puts "\nRendering prompt with test case variables..."
  prompt_result = render_prompt(client, template, test_case)

  rendered_messages = prompt_result[:rendered_messages]
  variables = prompt_result[:variables]

  puts "✓ Prompt rendered successfully"

  # Simulate the LLM grading interaction
  puts "\nSimulating LLM grading..."
  llm_result = simulate_llm_grading(rendered_messages, test_case)

  # Build complete messages array (prompt + response)
  complete_messages = rendered_messages + [
    { 'role' => 'assistant', 'content' => llm_result[:response] }
  ]

  # Prepare metadata to include with the completion
  metadata = {
    test_case_id: test_case['id'],
    student_grade: test_case['student_grade'],
    expected_score: test_case['expected_score'],
    actual_score: llm_result[:scoring_output]['total_score']
  }

  # Prepare call info
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

  # Record the completion to Freeplay
  puts "Recording completion to Freeplay..."
  completion_result = client.record_completion(
    session_id: session_id,
    messages: complete_messages,
    inputs: variables,
    metadata: metadata,
    call_info: call_info,
    trace_id: trace_id,
    prompt_version_id: PROMPT_VERSION_ID
  )

  # Check for any 2xx status code (200, 201, etc.)
  if completion_result[:status].between?(200, 299)
    puts "✓ Completion recorded successfully (status: #{completion_result[:status]})"
  else
    puts "✗ Failed to record completion (status: #{completion_result[:status]})"
    puts "  Response: #{completion_result[:body]}"
    return false
  end

  # Record the trace
  puts "Recording trace to Freeplay..."
  trace_result = client.record_trace(
    session_id: session_id,
    trace_id: trace_id,
    input: {
      test_case_id: test_case['id'],
      question: test_case['question'],
      student_answer: test_case['student_answer']
    },
    output: llm_result[:scoring_output],
    agent_name: 'assignment-evaluation-grader',
    metadata: metadata
  )

  # Check for any 2xx status code (200, 201, etc.)
  if trace_result[:status].between?(200, 299)
    puts "✓ Trace recorded successfully (status: #{trace_result[:status]})"
  else
    puts "✗ Failed to record trace (status: #{trace_result[:status]})"
    puts "  Response: #{trace_result[:body]}"
    return false
  end

  puts "\nSession ID: #{session_id}"
  puts "Trace ID: #{trace_id}"

  true
end

# Main execution
def main
  # Initialize Freeplay client
  config = FreeplayClient.configuration
  FreeplayClient::Utilities.validate_config!(config)
  validate_test_file!
  validate_prompt_config!

  client = FreeplayClient.create_client

  puts "=" * 80
  puts "Assignment Evaluation with Prompt Template - Freeplay Integration"
  puts "=" * 80

  # Fetch the prompt template once (not for every test case)
  puts "\nFetching prompt template from Freeplay..."
  puts "Template ID: #{PROMPT_TEMPLATE_ID}"
  puts "Version ID: #{PROMPT_VERSION_ID}"
  
  template = fetch_prompt_template(client)
  
  if template.nil?
    puts "\n✗ Failed to fetch prompt template. Exiting."
    exit 1
  end
  
  puts "✓ Prompt template fetched successfully"
  puts "  Template: #{template['prompt_template_name']}" if template['prompt_template_name']
  
  puts "\nLoading test cases from: #{TEST_CASES_FILE}"

  # Load test cases from JSON file
  test_cases = JSON.parse(File.read(TEST_CASES_FILE))
  puts "Found #{test_cases.length} test cases"

  # Process each test case
  successful = 0
  failed = 0

  test_cases.each_with_index do |test_case, index|
    if process_test_case(client, template, test_case, index, test_cases.length)
      successful += 1
    else
      failed += 1
    end

    # Small delay between requests to avoid rate limiting
    sleep(0.5) if index < test_cases.length - 1
  end

  # Summary
  puts "\n" + "=" * 80
  puts "Processing Complete"
  puts "=" * 80
  puts "Successfully processed: #{successful}/#{test_cases.length}"
  puts "Failed: #{failed}/#{test_cases.length}" if failed > 0
  puts "\nView your traces at: https://app.freeplay.ai"
end

# Run the script
main
