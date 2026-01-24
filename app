from openai import OpenAI
from datetime import datetime
import json
from bs4 import BeautifulSoup
import requests
import urllib3

# Disable SSL warnings if SSL verification is disabled
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

# Configuration
CONFIG = {
    "base_url": "https://api.openai.com/v1",  # Change to your OpenAI-compatible endpoint
    "api_key": "your-api-key-here",
    "model_name": "gpt-4o",  # or gpt-4, gpt-3.5-turbo, etc.
    "disable_ssl": False,  # Set to True to disable SSL verification
    "proxy_url": None,  # e.g., "http://proxy.company.com:8080"
}

# Initialize OpenAI client
client = OpenAI(
    base_url=CONFIG["base_url"],
    api_key=CONFIG["api_key"],
    http_client=None if not CONFIG["proxy_url"] else __import__('httpx').Client(
        proxies=CONFIG["proxy_url"],
        verify=not CONFIG["disable_ssl"]
    )
)


def call_tool(name, **kwargs):
    if name == "get_time":
        return {"time": datetime.now().isoformat()}

    elif name == "web_search":
        query = kwargs.get("query", "")
        return perform_web_search(query)

    return {"result": None}


def format_response_with_citations(message, search_results):
    """Format the response to show text with actual source URLs"""
    if not message or not message.content:
        return "No response generated."

    full_text = message.content

    # OpenAI doesn't have native citation chunking like Mistral
    # We'll append sources at the end if available
    if search_results:
        full_text += "\n\n" + "=" * 60
        full_text += "\nSources:\n"
        
        for idx, source in enumerate(search_results, 1):
            full_text += f"\n[{idx}] {source['title']}\n"
            full_text += f"    🔗 {source['link']}\n"
            if source.get('snippet'):
                full_text += f"    {source['snippet'][:100]}...\n"

    return full_text


def perform_web_search(query):
    """Perform a web search using DuckDuckGo"""
    try:
        # Using DuckDuckGo HTML search (no API key needed)
        url = f"https://html.duckduckgo.com/html/?q={requests.utils.quote(query)}"
        headers = {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
        }

        # Handle proxy and SSL settings for web search
        proxies = {"http": CONFIG["proxy_url"], "https": CONFIG["proxy_url"]} if CONFIG["proxy_url"] else None
        verify_ssl = not CONFIG["disable_ssl"]

        response = requests.get(
            url, 
            headers=headers, 
            timeout=10,
            proxies=proxies,
            verify=verify_ssl
        )
        soup = BeautifulSoup(response.text, 'html.parser')

        results = []
        for result in soup.find_all('div', class_='result')[:5]:  # Get top 5 results
            title_tag = result.find('a', class_='result__a')
            snippet_tag = result.find('a', class_='result__snippet')

            if title_tag:
                title = title_tag.get_text(strip=True)
                link = title_tag.get('href', '')
                snippet = snippet_tag.get_text(strip=True) if snippet_tag else ""

                results.append({
                    "title": title,
                    "link": link,
                    "snippet": snippet
                })

        return {
            "query": query,
            "results": results,
            "count": len(results)
        }

    except Exception as e:
        return {
            "error": f"Search failed: {str(e)}",
            "query": query
        }


def run_agent(prompt):
    messages = [{"role": "user", "content": prompt}]
    search_results_cache = []  # Store search results for citation mapping

    # Define available tools (OpenAI function calling format)
    tools = [
        {
            "type": "function",
            "function": {
                "name": "get_time",
                "description": "Returns the current time in ISO format",
                "parameters": {
                    "type": "object",
                    "properties": {},
                    "required": []
                }
            }
        },
        {
            "type": "function",
            "function": {
                "name": "web_search",
                "description": "Search the web for current information, news, facts, or any topic. Use this when you need up-to-date information or don't know the answer.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "query": {
                            "type": "string",
                            "description": "The search query to look up on the web"
                        }
                    },
                    "required": ["query"]
                }
            }
        }
    ]

    while True:
        response = client.chat.completions.create(
            model=CONFIG["model_name"],
            messages=messages,
            tools=tools,
            tool_choice="auto"
        )

        message = response.choices[0].message

        # Check if model wants to call a function
        if message.tool_calls:
            # Add assistant's message with tool calls to history
            messages.append({
                "role": "assistant",
                "content": message.content,
                "tool_calls": [
                    {
                        "id": tc.id,
                        "type": tc.type,
                        "function": {
                            "name": tc.function.name,
                            "arguments": tc.function.arguments
                        }
                    }
                    for tc in message.tool_calls
                ]
            })

            # Process each tool call
            for tool_call in message.tool_calls:
                function_name = tool_call.function.name
                function_args_str = tool_call.function.arguments

                # Parse JSON string to dictionary
                function_args = json.loads(function_args_str) if function_args_str else {}

                # Execute the function
                print(f"\nCalling tool: {function_name}")
                print(f"Arguments: {function_args}")

                result = call_tool(function_name, **function_args)

                # Cache search results for citation mapping
                if function_name == "web_search" and "results" in result:
                    search_results_cache = result["results"]
                    print(f"Found {len(search_results_cache)} results\n")

                # Add function response to messages
                messages.append({
                    "role": "tool",
                    "name": function_name,
                    "content": json.dumps(result),
                    "tool_call_id": tool_call.id
                })
        else:
            # Return the formatted text response with actual source URLs
            return format_response_with_citations(message, search_results_cache)


# Test examples
if __name__ == "__main__":
    # Test time query
    print("=" * 60)
    print("Query: What time is it?")
    print("=" * 60)
    print(run_agent("What time is it?"))

    print("\n" + "=" * 60)
    print("Query: What's the latest news about AI?")
    print("=" * 60)
    print(run_agent("What's the latest news about AI?"))

    print("\n" + "=" * 60)
    print("Query: Who won the latest Nobel Prize in Physics?")
    print("=" * 60)
    print(run_agent("Who won the latest Nobel Prize in Physics?"))
