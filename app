import os
import cv2
import base64
from dotenv import load_dotenv
from openai import OpenAI

# Load environment variables from .env
load_dotenv()

# Configuration from .env
base_url = os.getenv("openai_base_url")  # e.g., "https://api.mistral.ai/v1"
api_key = os.getenv("openai_api_key")
model_name = os.getenv("openai_model_name", "mistral-small-latest")  # Use mistral-small-latest or similar vision model
proxy_url = os.getenv("proxy_url")
disable_ssl = os.getenv("disable_ssl", "False").lower() == "true"

# Setup OpenAI client compatible with Mistral API
client_kwargs = {
    "api_key": api_key,
    "base_url": base_url,
}

if proxy_url:
    client_kwargs["http_client"] = openai.ProxyClient(proxy=proxy_url)

# Note: OpenAI SDK does not have a direct disable_ssl_verify option.
# If needed, use custom requests session with verify=False (insecure, not recommended):
if disable_ssl:
    import requests
    session = requests.Session()
    session.verify = False
    from openai import httpx
    client_kwargs["http_client"] = httpx.Client(proxy=proxy_url if proxy_url else None, transport=httpx.HTTPTransport(session=session))

client = OpenAI(**client_kwargs)

def extract_frames_from_video(video_path, num_frames=10, interval_seconds=5):
    """
    Extract key frames from a video using OpenCV.
    Samples frames at regular intervals (default every 5 seconds, up to 10 frames).
    """
    vidcap = cv2.VideoCapture(video_path)
    if not vidcap.isOpened():
        raise ValueError("Could not open video file.")

    fps = vidcap.get(cv2.CAP_PROP_FPS)
    total_frames = int(vidcap.get(cv2.CAP_PROP_FRAME_COUNT))
    duration = total_frames / fps if fps > 0 else 0

    frames = []
    frame_count = 0
    success, image = vidcap.read()

    target_intervals = [i * (duration / num_frames) for i in range(1, num_frames)]
    next_target = 0

    while success:
        current_time = frame_count / fps if fps > 0 else 0
        if next_target < len(target_intervals) and current_time >= target_intervals[next_target]:
            # Convert BGR to RGB (optional, but JPEG is fine as-is)
            _, buffer = cv2.imencode(".jpg", image)
            base64_image = base64.b64encode(buffer).decode("utf-8")
            frames.append(f"data:image/jpeg;base64,{base64_image}")
            next_target += 1
        if next_target >= len(target_intervals):
            break
        success, image = vidcap.read()
        frame_count += 1

    vidcap.release()
    if not frames:
        raise ValueError("No frames extracted from video.")
    return frames

def analyze_video(video_path, prompt="Describe what is happening in this video in detail.", num_frames=10):
    """
    Analyze a video by extracting frames and sending them to the Mistral vision model.
    """
    print(f"Extracting {num_frames} frames from {video_path}...")
    frames_base64 = extract_frames_from_video(video_path, num_frames=num_frames)

    # Build content with text prompt + multiple images
    content = [{"type": "text", "text": prompt}]
    for frame in frames_base64:
        content.append({
            "type": "image_url",
            "image_url": {"url": frame}
        })

    messages = [
        {"role": "user", "content": content}
    ]

    print("Sending request to Mistral vision model...")
    response = client.chat.completions.create(
        model=model_name,
        messages=messages,
        max_tokens=1024,
        temperature=0.7,
    )

    analysis = response.choices[0].message.content
    return analysis

# Example usage
if __name__ == "__main__":
    video_file = "path/to/your/video.mp4"  # Replace with your video path
    result = analyze_video(video_file, prompt="Summarize the key events and actions in this video step by step.")
    print("\nVideo Analysis:\n")
    print(result)
