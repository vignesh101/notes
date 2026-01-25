from openai import OpenAI
from datetime import datetime
import json
from bs4 import BeautifulSoup
import requests
import urllib3
import os
import subprocess
import sys

# Disable SSL warnings
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

# Configuration
CONFIG = {
    "base_url": "https://api.openai.com/v1",
    "api_key": os.getenv("OPENAI_API_KEY", "your-api-key-here"),  # Use environment variable
    "model_name": "gpt-4o",
    "disable_ssl": False,
    "proxy_url": None,
    "max_iterations": 15,
}

# Initialize OpenAI client with proper error handling
try:
    client = OpenAI(
        base_url=CONFIG["base_url"],
        api_key=CONFIG["api_key"],
        http_client=None if not CONFIG["proxy_url"] else __import__('httpx').Client(
            proxies=CONFIG["proxy_url"],
            verify=not CONFIG["disable_ssl"]
        )
    )
except Exception as e:
    print(f"❌ Error initializing OpenAI client: {e}")
    print("Please set your API key: export OPENAI_API_KEY='your-key-here'")
    sys.exit(1)


def call_tool(name, **kwargs):
    """Execute tools locally - THIS RUNS ON YOUR MACHINE"""
    print(f"\n🔧 Tool: {name}")
    
    if name == "get_time":
        return {"time": datetime.now().isoformat()}

    elif name == "web_search":
        query = kwargs.get("query", "")
        return perform_web_search(query)

    elif name == "execute_python":
        code = kwargs.get("code", "")
        return execute_python_code(code)

    elif name == "execute_shell":
        command = kwargs.get("command", "")
        return execute_shell_command(command)

    elif name == "read_file":
        filepath = kwargs.get("filepath", "")
        return read_file(filepath)

    elif name == "write_file":
        filepath = kwargs.get("filepath", "")
        content = kwargs.get("content", "")
        return write_file(filepath, content)

    elif name == "list_directory":
        directory = kwargs.get("directory", ".")
        return list_directory(directory)

    return {"error": f"Unknown tool: {name}"}


def perform_web_search(query):
    """Web search using DuckDuckGo"""
    try:
        url = f"https://html.duckduckgo.com/html/?q={requests.utils.quote(query)}"
        headers = {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'}
        
        proxies = {"http": CONFIG["proxy_url"], "https": CONFIG["proxy_url"]} if CONFIG["proxy_url"] else None
        
        response = requests.get(url, headers=headers, timeout=10, proxies=proxies, verify=not CONFIG["disable_ssl"])
        soup = BeautifulSoup(response.text, 'html.parser')

        results = []
        for result in soup.find_all('div', class_='result')[:5]:
            title_tag = result.find('a', class_='result__a')
            snippet_tag = result.find('a', class_='result__snippet')

            if title_tag:
                results.append({
                    "title": title_tag.get_text(strip=True),
                    "link": title_tag.get('href', ''),
                    "snippet": snippet_tag.get_text(strip=True) if snippet_tag else ""
                })

        print(f"   ✅ Found {len(results)} results")
        return {"query": query, "results": results, "count": len(results)}

    except Exception as e:
        return {"error": f"Search failed: {str(e)}"}


def execute_python_code(code):
    """Execute Python code LOCALLY"""
    try:
        print(f"   🐍 Running Python code...")
        temp_file = f"temp_{datetime.now().timestamp()}.py"
        
        with open(temp_file, 'w') as f:
            f.write(code)
        
        result = subprocess.run(
            [sys.executable, temp_file],
            capture_output=True,
            text=True,
            timeout=30
        )
        
        os.remove(temp_file)
        
        print(f"   ✅ Executed (exit code: {result.returncode})")
        return {
            "stdout": result.stdout,
            "stderr": result.stderr,
            "exit_code": result.returncode,
            "success": result.returncode == 0
        }
    except Exception as e:
        return {"error": str(e), "success": False}


def execute_shell_command(command):
    """Execute shell command LOCALLY"""
    try:
        print(f"   💻 Running: {command}")
        result = subprocess.run(
            command,
            shell=True,
            capture_output=True,
            text=True,
            timeout=30
        )
        print(f"   ✅ Executed (exit code: {result.returncode})")
        return {
            "stdout": result.stdout,
            "stderr": result.stderr,
            "exit_code": result.returncode,
            "success": result.returncode == 0
        }
    except Exception as e:
        return {"error": str(e), "success": False}


def read_file(filepath):
    """Read file content"""
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()
        print(f"   ✅ Read {len(content)} characters from {filepath}")
        return {"filepath": filepath, "content": content, "size": len(content), "success": True}
    except Exception as e:
        return {"error": str(e), "success": False}


def write_file(filepath, content):
    """Write content to file"""
    try:
        os.makedirs(os.path.dirname(filepath) if os.path.dirname(filepath) else '.', exist_ok=True)
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(content)
        print(f"   ✅ Wrote {len(content)} characters to {filepath}")
        return {"filepath": filepath, "size": len(content), "success": True}
    except Exception as e:
        return {"error": str(e), "success": False}


def list_directory(directory):
    """List files in directory"""
    try:
        items = []
        for item in os.listdir(directory):
            path = os.path.join(directory, item)
            items.append({
                "name": item,
                "is_dir": os.path.isdir(path),
                "size": os.path.getsize(path) if os.path.isfile(path) else 0
            })
        print(f"   ✅ Found {len(items)} items in {directory}")
        return {"directory": directory, "items": items, "count": len(items), "success": True}
    except Exception as e:
        return {"error": str(e), "success": False}


def format_response(message, search_results):
    """Format final response with citations"""
    if not message or not message.content:
        return "No response generated."

    response_text = message.content

    if search_results:
        response_text += "\n\n" + "=" * 70
        response_text += "\n📚 SOURCES:\n"
        for idx, source in enumerate(search_results, 1):
            response_text += f"\n[{idx}] {source['title']}\n"
            response_text += f"    🔗 {source['link']}\n"

    return response_text


def run_agent(user_query, verbose=True):
    """Main agent loop - runs locally without restrictions"""
    
    messages = [
        {
            "role": "system",
            "content": "You are a helpful AI assistant with access to tools. Use them when needed to help the user. You can execute code, search the web, and work with files."
        },
        {
            "role": "user",
            "content": user_query
        }
    ]
    
    search_results_cache = []
    iteration = 0

    # Tool definitions - OpenAI format
    tools = [
        {
            "type": "function",
            "function": {
                "name": "get_time",
                "description": "Get current date and time",
                "parameters": {"type": "object", "properties": {}}
            }
        },
        {
            "type": "function",
            "function": {
                "name": "web_search",
                "description": "Search the web for information",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "query": {"type": "string", "description": "Search query"}
                    },
                    "required": ["query"]
                }
            }
        },
        {
            "type": "function",
            "function": {
                "name": "execute_python",
                "description": "Execute Python code and return output",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "code": {"type": "string", "description": "Python code to execute"}
                    },
                    "required": ["code"]
                }
            }
        },
        {
            "type": "function",
            "function": {
                "name": "execute_shell",
                "description": "Execute shell command",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "command": {"type": "string", "description": "Shell command"}
                    },
                    "required": ["command"]
                }
            }
        },
        {
            "type": "function",
            "function": {
                "name": "read_file",
                "description": "Read file contents",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "filepath": {"type": "string", "description": "File path"}
                    },
                    "required": ["filepath"]
                }
            }
        },
        {
            "type": "function",
            "function": {
                "name": "write_file",
                "description": "Write content to file",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "filepath": {"type": "string"},
                        "content": {"type": "string"}
                    },
                    "required": ["filepath", "content"]
                }
            }
        },
        {
            "type": "function",
            "function": {
                "name": "list_directory",
                "description": "List directory contents",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "directory": {"type": "string", "default": "."}
                    }
                }
            }
        }
    ]

    # Agent loop
    while iteration < CONFIG["max_iterations"]:
        iteration += 1
        if verbose:
            print(f"\n{'='*70}\n🤖 Iteration {iteration}\n{'='*70}")

        try:
            response = client.chat.completions.create(
                model=CONFIG["model_name"],
                messages=messages,
                tools=tools,
                tool_choice="auto",
                temperature=0.7
            )

            message = response.choices[0].message

            # Check for tool calls
            if message.tool_calls:
                # Add assistant message
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

                # Execute each tool
                for tool_call in message.tool_calls:
                    function_name = tool_call.function.name
                    function_args = json.loads(tool_call.function.arguments or "{}")

                    # Call the tool
                    result = call_tool(function_name, **function_args)

                    # Cache search results
                    if function_name == "web_search" and "results" in result:
                        search_results_cache = result["results"]

                    # Add tool result to conversation
                    messages.append({
                        "role": "tool",
                        "name": function_name,
                        "content": json.dumps(result),
                        "tool_call_id": tool_call.id
                    })

            else:
                # Final answer
                return format_response(message, search_results_cache)

        except Exception as e:
            return f"❌ Error: {str(e)}"

    return "⚠️ Max iterations reached"


def interactive_mode():
    """Interactive chat mode"""
    print("\n" + "="*70)
    print("🚀 LOCAL AI AGENT - INTERACTIVE MODE")
    print("="*70)
    print("Commands: 'exit', 'quit', 'clear'\n")
    
    conversation_history = []
    
    while True:
        try:
            user_input = input("\n👤 You: ").strip()
            
            if user_input.lower() in ['exit', 'quit']:
                print("\n👋 Goodbye!")
                break
            
            if user_input.lower() == 'clear':
                conversation_history = []
                print("\n✅ Conversation cleared")
                continue
            
            if not user_input:
                continue
            
            print("\n🤖 Agent:")
            response = run_agent(user_input, verbose=True)
            print(f"\n{response}")
            
        except KeyboardInterrupt:
            print("\n\n👋 Goodbye!")
            break
        except Exception as e:
            print(f"\n❌ Error: {str(e)}")


if __name__ == "__main__":
    # Quick tests
    print("\n🧪 RUNNING TESTS...\n")
    
    print("1️⃣ Time Test:")
    print(run_agent("What time is it?", verbose=False))
    
    print("\n2️⃣ Web Search Test:")
    print(run_agent("What's the latest news about AI?", verbose=False))
    
    print("\n3️⃣ File Test:")
    print(run_agent("Create a file called 'hello.txt' with 'Hello World!'", verbose=False))
    
    # Start interactive mode
    print("\n" + "="*70)
    interactive_mode()
