import os
import cv2
import base64
import math
from dotenv import load_dotenv
from openai import OpenAI
import httpx

# Load .env variables
load_dotenv()

base_url = os.getenv("openai_base_url")
api_key = os.getenv("openai_api_key")
model_name = os.getenv("openai_model_name", "pixtral-12b-2409")  # or mistral-small-latest
proxy_url = os.getenv("proxy_url")
disable_ssl = os.getenv("disable_ssl", "False").lower() == "true"

# Setup client with proxy and optional SSL disable
client_kwargs = {"api_key": api_key, "base_url": base_url}

if proxy_url or disable_ssl:
    http_client = httpx.Client(
        proxy=proxy_url if proxy_url else None,
        verify=False if disable_ssl else True  # WARNING: verify=False is insecure
    )
    client_kwargs["http_client"] = http_client

client = OpenAI(**client_kwargs)


def extract_frames_from_video(video_path, num_frames=8):
    """Extract evenly spaced frames from video and return as base64 data URLs"""
    vidcap = cv2.VideoCapture(video_path)
    if not vidcap.isOpened():
        raise ValueError("Could not open video file.")

    fps = vidcap.get(cv2.CAP_PROP_FPS)
    total_frames_count = int(vidcap.get(cv2.CAP_PROP_FRAME_COUNT))
    duration = total_frames_count / fps if fps > 0 else 0

    frames = []
    success, image = vidcap.read()
    frame_idx = 0

    # Target timestamps for even sampling
    if duration > 0 and num_frames > 0:
        intervals = [i * duration / (num_frames + 1) for i in range(1, num_frames + 1)]  # Adjusted for better spacing
    else:
        intervals = []

    next_interval_idx = 0

    while success:
        current_time = frame_idx / fps if fps > 0 else 0

        if next_interval_idx < len(intervals) and current_time >= intervals[next_interval_idx]:
            _, buffer = cv2.imencode(".jpg", image)
            base64_img = base64.b64encode(buffer).decode("utf-8")
            frames.append(f"data:image/jpeg;base64,{base64_img}")
            next_interval_idx += 1

        if len(frames) >= num_frames:
            break

        success, image = vidcap.read()
        frame_idx += 1

    vidcap.release()
    return frames


def analyze_video(video_path,
                  prompt="Describe what is happening in this video in detail, step by step.",
                  seconds_per_frame=4.0,
                  max_frames_per_request=8):
    """
    Fully automatic video analysis:
    - Calculates appropriate sampling rate
    - Extracts all frames upfront
    - Splits and sends in chunks if needed
    - Returns clean final summary (no technical details shown)
    """
    # Get video duration
    vidcap = cv2.VideoCapture(video_path)
    fps = vidcap.get(cv2.CAP_PROP_FPS)
    total_video_frames = int(vidcap.get(cv2.CAP_PROP_FRAME_COUNT))
    duration_seconds = total_video_frames / fps if fps > 0 else 0
    vidcap.release()

    if duration_seconds == 0:
        raise ValueError("Could not read video duration.")

    # Decide how many frames to sample (1 every ~seconds_per_frame)
    desired_frames = max(4, int(duration_seconds / seconds_per_frame))  # at least 4
    total_sampled_frames = min(desired_frames, max_frames_per_request * 4)  # cap at 32 for cost/reasonableness

    # Extract ALL frames upfront
    print("Extracting frames...")
    all_frames_base64 = extract_frames_from_video(video_path, num_frames=total_sampled_frames)

    # Calculate chunks
    chunks = math.ceil(total_sampled_frames / max_frames_per_request)

    all_part_descriptions = []

    print("Analyzing video...")

    for chunk_idx in range(chunks):
        start = chunk_idx * max_frames_per_request
        end = min(start + max_frames_per_request, total_sampled_frames)
        chunk_frames = all_frames_base64[start:end]

        content = [{"type": "text", "text": prompt}]
        for frame in chunk_frames:
            content.append({
                "type": "image_url",
                "image_url": {"url": frame}
            })

        messages = [{"role": "user", "content": content}]

        response = client.chat.completions.create(
            model=model_name,
            messages=messages,
            max_tokens=1024,
            temperature=0.7,
        )

        description = response.choices[0].message.content.strip()
        all_part_descriptions.append(description)

    # Combine all parts into one final coherent summary
    if len(all_part_descriptions) == 1:
        final_summary = all_part_descriptions[0]
    else:
        combine_prompt = (
            "The following are descriptions of different segments of the same video:\n\n" +
            "\n\n---\n\n".join(all_part_descriptions) +
            "\n\nCombine these into one clear, chronological, and detailed summary of the entire video."
        )

        final_response = client.chat.completions.create(
            model=model_name,
            messages=[{"role": "user", "content": combine_prompt}],
            max_tokens=1024,
            temperature=0.5,
        )
        final_summary = final_response.choices[0].message.content.strip()

    return final_summary


# ================ RUN EXAMPLE ================
if __name__ == "__main__":
    video_file = "C:/Users/h75378/Downloads/sample_1.mp4"  # Change to your video path

    result = analyze_video(
        video_file,
        prompt="Describe the key events, actions, people, objects, and scene changes in chronological order.",
        seconds_per_frame=4.0  # Adjust: lower = more detail (and cost), higher = faster
    )

    print("\n" + "="*60)
    print("VIDEO ANALYSIS")
    print("="*60)
    print(result)
