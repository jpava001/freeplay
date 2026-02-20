# Freeplay Ruby Scripts

This folder contains Ruby scripts demonstrating how to integrate with the Freeplay API for LLM observability and prompt management.

## Setup

1. Install dependencies:
   ```bash
   gem install dotenv
   ```

2. Copy `.env.example` to `.env` and fill in your Freeplay credentials.

## Scripts

### 1. Simple Trace (`1_simple_trace.rb`)

A minimal example demonstrating the basics of Freeplay integration. Simulates a simple "Hello world!" LLM interaction and records both a completion and trace to Freeplay.

**What it does:**
- Simulates an LLM call with a hardcoded response
- Records the completion (messages, model info, token usage)
- Records a trace for grouping interactions

**Use this to:** Understand the basic Freeplay API workflow.

---

### 2. Assignment Evaluation Traces (`2_assignment_evaluation_traces.rb`)

Processes reading comprehension test cases and records grading interactions to Freeplay. Builds prompts manually without using Freeplay templates.

**What it does:**
- Loads test cases from `data/reading_comprehension_test_cases.json`
- Builds a grading prompt for each test case (student grade, passage, question, rubric, answer)
- Simulates LLM grading using pre-defined scoring outputs
- Records completions and traces with metadata (test case ID, expected vs actual scores)

**Use this to:** Process batch evaluations and track LLM grading performance.

---

### 3. Get Prompt (`3_get_prompt.rb`)

Fetches and displays a Freeplay prompt template by name. A simple utility for inspecting prompt templates.

**What it does:**
- Fetches the "greeting" prompt template from the "latest" environment
- Displays template metadata (ID, version, model, provider)
- Shows all message content including history placeholders

**Use this to:** Inspect prompt templates stored in Freeplay.

---

### 4. Get Prompt with Variables (`4_get_prompt_with_variables.rb`)

End-to-end example of fetching a prompt template, rendering it with variables, simulating an LLM response, and recording everything to Freeplay.

**What it does:**
- Fetches a prompt template by template ID and version ID
- Renders the template with variables (`name`, `language`)
- Simulates a personalized greeting response
- Records both completion (linked to prompt version) and trace

**Use this to:** Understand the full workflow of using Freeplay prompt templates with variable substitution and observability.

---

### 5. Assignment Evaluation with Prompt Template (`5_assignment_evaluation_with_prompt_template.rb`)

Combines prompt template management with batch test case processing. The most comprehensive example.

**What it does:**
- Fetches a prompt template once at startup
- Loads test cases from `data/assignment_evaluation_test_cases.json`
- For each test case:
  - Renders the prompt template with test case variables
  - Simulates LLM grading
  - Records completion (linked to prompt version) and trace with metadata
- Reports success/failure summary

**Use this to:** Run batch evaluations using managed prompt templates with full Freeplay observability.

## Data Files

The scripts expect JSON test case files in the `data/` subdirectory:
- `reading_comprehension_test_cases.json` - Used by script 2
- `assignment_evaluation_test_cases.json` - Used by script 5

## Shared Library

All scripts use `lib/freeplay_client.rb` which provides:
- API client initialization
- Completion and trace recording
- Prompt template fetching and rendering
- Utility functions (token estimation, config validation)
