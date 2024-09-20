#!/bin/bash

# Check if a question was provided as a command-line argument
if [ $# -gt 0 ]; then
  question="$*"
else
  read -p "Enter your question: " question
fi

# Check if OPENAI_API_KEY is set
if [ -z "$OPENAI_API_KEY" ]; then
  echo "Please set your OpenAI API key in the OPENAI_API_KEY environment variable."
  exit 1
fi

# Set the model to use
MODEL="gpt-4"

# Make the API call and output the response
curl -s https://api.openai.com/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -d '{
    "model": "'"$MODEL"'",
    "messages": [{"role": "user", "content": "'"${question//\"/\\\"}"'"}],
    "max_tokens": 100,
    "temperature": 0.7
}' | jq -r '.choices[0].message.content'
