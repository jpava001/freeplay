#!/usr/bin/env ruby
# frozen_string_literal: true

# Ruby script to process reading comprehension test cases and send traces to Freeplay
# This simulates LLM grading interactions for educational assessment
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
FREEPLAY_PROMPT_VERSION_ID = ENV['FREEPLAY_PROMPT_VERSION_ID'] # Optional
FREEPLAY_API_URL = ENV.fetch('FREEPLAY_API_URL', 'https://app.freeplay.ai/api/v2')

# Path to test cases
TEST_CASES_FILE = File.join(__dir__, 'data', 'reading_comprehension_test_cases.json')

def validate_config!
  missing = []
  missing << 'FREEPLAY_API_KEY' unless FREEPLAY_API_KEY
  missing << 'FREEPLAY_PROJECT_ID' unless FREEPLAY_PROJECT_ID

  unless missing.empty?
    puts "Error: Missing required environment variables: #{missing.join(', ')}"
    puts "\nPlease set them in your .env file"
    exit 1
  end

  unless File.exist?(TEST_CASES_FILE)
    puts "Error: Test cases file not found at #{TEST_CASES_FILE}"
    exit 1
  end
end

# Build the grading prompt for the LLM
def build_grading_prompt(test_case)
  <<~PROMPT
    You are an expert educational assessment tool. Grade the following student answer based on the provided rubric.

    **Passage:**
    #{test_case['passage']}

    **Question:**
    #{test_case['question']}

    **Rubric:**
    #{test_case['rubric']}

    **Student's Answer:**
    #{test_case['answer']}

    Please evaluate this answer according to the rubric and provide:
    1. A score for each criterion
    2. Reasoning for each score
    3. A total score
    4. Overall feedback
  PROMPT
end

# Simulate LLM grading (no actual API call - using test case data)
def simulate_llm_grading(test_case)
  prompt = build_grading_prompt(test_case)
  
  # In a real scenario, you would call an LLM API here
  # For this simulation, we use the llm_scoring_output from the test case
  scoring_output = test_case['llm_scoring_output']
  
  # Format the response as if it came from an LLM
  response_text = format_scoring_response(scoring_output)
  
  {
    prompt: prompt,
    response: response_text,
    scoring_output: scoring_output,
    model: 'gpt-4o',
    provider: 'openai',
    input_tokens: estimate_tokens(prompt),
    output_tokens: estimate_tokens(response_text)
  }
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

# Simple token estimation (roughly 4 characters per token)
def estimate_tokens(text)
  (text.length / 4.0).ceil
end

# Record a completion to Freeplay with custom metadata
def record_completion(session_id:, messages:, inputs:, metadata:, call_info: nil, trace_id: nil)
  uri = URI("#{FREEPLAY_API_URL}/projects/#{FREEPLAY_PROJECT_ID}/sessions/#{session_id}/completions")

  payload = {
    messages: messages,
    inputs: inputs
  }

  # Only include prompt_info if we have a prompt template version ID
  if FREEPLAY_PROMPT_VERSION_ID && !FREEPLAY_PROMPT_VERSION_ID.empty?
    payload[:prompt_info] = {
      prompt_template_version_id: FREEPLAY_PROMPT_VERSION_ID,
      environment: 'latest'
    }
  end

  # Add session metadata (includes student_grade, expected_score, etc.)
  payload[:session_info] = {
    custom_metadata: metadata
  } if metadata && !metadata.empty?

  # Add trace association if provided
  payload[:trace_info] = { trace_id: trace_id } if trace_id

  # Add call metadata if provided (timing, tokens, etc.)
  payload[:call_info] = call_info if call_info

  make_request(uri, payload)
end

# Record a trace to Freeplay
def record_trace(session_id:, trace_id:, input:, output:, metadata: {})
  uri = URI("#{FREEPLAY_API_URL}/projects/#{FREEPLAY_PROJECT_ID}/sessions/#{session_id}/traces/id/#{trace_id}")

  payload = {
    input: input,
    output: output,
    agent_name: 'reading-comprehension-grader'
  }

  # Add custom metadata to trace
  payload[:custom_metadata] = metadata if metadata && !metadata.empty?

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

  response = http.request(request)

  {
    status: response.code.to_i,
    body: response.body.empty? ? {} : JSON.parse(response.body)
  }
rescue StandardError => e
  puts "Error making request: #{e.message}"
  { status: 0, error: e.message }
end

# Process a single test case
def process_test_case(test_case, index, total)
  puts "\n" + "=" * 80
  puts "Processing test case #{index + 1}/#{total}: #{test_case['id']}"
  puts "=" * 80

  # Generate unique IDs for this interaction
  session_id = SecureRandom.uuid
  trace_id = SecureRandom.uuid

  # Simulate the LLM grading interaction
  puts "\nSimulating LLM grading..."
  llm_result = simulate_llm_grading(test_case)

  # Build messages array (prompt and response)
  messages = [
    { role: 'user', content: llm_result[:prompt] },
    { role: 'assistant', content: llm_result[:response] }
  ]

  # Prepare inputs (variables used in the prompt)
  inputs = {
    passage: test_case['passage'],
    question: test_case['question'],
    rubric: test_case['rubric'],
    student_answer: test_case['answer']
  }

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
  completion_result = record_completion(
    session_id: session_id,
    messages: messages,
    inputs: inputs,
    metadata: metadata,
    call_info: call_info,
    trace_id: trace_id
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
  trace_result = record_trace(
    session_id: session_id,
    trace_id: trace_id,
    input: {
      test_case_id: test_case['id'],
      question: test_case['question'],
      student_answer: test_case['answer']
    },
    output: llm_result[:scoring_output],
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
  validate_config!

  puts "=" * 80
  puts "Reading Comprehension Test Cases - Freeplay Integration"
  puts "=" * 80
  puts "\nLoading test cases from: #{TEST_CASES_FILE}"

  # Load test cases from JSON file
  test_cases = JSON.parse(File.read(TEST_CASES_FILE))
  puts "Found #{test_cases.length} test cases"

  # Process each test case
  successful = 0
  failed = 0

  test_cases.each_with_index do |test_case, index|
    if process_test_case(test_case, index, test_cases.length)
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
