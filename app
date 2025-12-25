import os
import cv2
import base64
import math
from dotenv import load_dotenv
from openai import OpenAI
import httpx
from moviepy.editor import VideoFileClip
import whisper  # pip install openai-whisper

# Load .env variables
load_dotenv()

base_url = os.getenv("openai_base_url")
api_key = os.getenv("openai_api_key")
model_name = os.getenv("openai_model_name", "pixtral-12b-2409")  # Vision-capable model
proxy_url = os.getenv("proxy_url")
disable_ssl = os.getenv("disable_ssl", "False").lower() == "true"

# Setup client
client_kwargs = {"api_key": api_key, "base_url": base_url}

if proxy_url or disable_ssl:
    http_client = httpx.Client(
        proxy=proxy_url if proxy_url else None,
        verify=False if disable_ssl else True
    )
    client_kwargs["http_client"] = http_client

client = OpenAI(**client_kwargs)

# Load Whisper model once (use "base" for speed, "large-v3" for max accuracy)
whisper_model = whisper.load_model("base")  # Options: tiny, base, small, medium, large-v3


def extract_frames_from_video(video_path, num_frames=8):
    """Extract evenly spaced frames → base64 data URLs"""
    vidcap = cv2.VideoCapture(video_path)
    if not vidcap.isOpened():
        raise ValueError("Could not open video file.")

    fps = vidcap.get(cv2.CAP_PROP_FPS)
    total_frames_count = int(vidcap.get(cv2.CAP_PROP_FRAME_COUNT))
    duration = total_frames_count / fps if fps > 0 else 0

    frames = []
    success, image = vidcap.read()
    frame_idx = 0

    if duration > 0 and num_frames > 0:
        intervals = [i * duration / (num_frames + 1) for i in range(1, num_frames + 1)]
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


def transcribe_audio(video_path):
    """Extract audio from video and transcribe with Whisper"""
    print("Extracting and transcribing audio...")
    
    # Extract audio temporarily
    video_clip = VideoFileClip(video_path)
    audio_path = "temp_audio.wav"
    video_clip.audio.write_audiofile(audio_path, verbose=False, logger=None)
    video_clip.close()
    
    # Transcribe
    result = whisper_model.transcribe(audio_path, fp16=False)  # fp16=False for CPU compatibility
    transcript = result["text"].strip()
    
    # Optional: Get segments with timestamps
    segments = "\n".join([f"[{seg['start']:.1f}s → {seg['end']:.1f}s] {seg['text'].strip()}" 
                          for seg in result["segments"]])
    
    # Clean up temp file
    os.remove(audio_path)
    
    return transcript, segments


def analyze_video_with_audio(video_path,
                             visual_prompt="Describe the key events, actions, people, objects, and scene changes in chronological order.",
                             seconds_per_frame=4.0,
                             max_frames_per_request=8):
    """
    Full video + audio analysis:
    - Visual: Sampled frames (chunked if needed)
    - Audio: Full transcript with timestamps
    - Final combined detailed report
    """
    # 1. Get video duration
    vidcap = cv2.VideoCapture(video_path)
    fps = vidcap.get(cv2.CAP_PROP_FPS)
    total_video_frames = int(vidcap.get(cv2.CAP_PROP_FRAME_COUNT))
    duration_seconds = total_video_frames / fps if fps > 0 else 0
    vidcap.release()

    if duration_seconds == 0:
        raise ValueError("Could not read video duration.")

    # 2. Calculate frames to sample
    desired_frames = max(4, int(duration_seconds / seconds_per_frame))
    total_sampled_frames = min(desired_frames, max_frames_per_request * 4)  # Cap at 32

    # 3. Extract all visual frames upfront
    print("Extracting visual frames...")
    all_frames_base64 = extract_frames_from_video(video_path, num_frames=total_sampled_frames)

    # 4. Transcribe audio
    full_transcript, timed_transcript = transcribe_audio(video_path)

    # 5. Visual analysis in chunks
    chunks = math.ceil(total_sampled_frames / max_frames_per_request)
    visual_descriptions = []

    print("Analyzing visuals...")
    for chunk_idx in range(chunks):
        start = chunk_idx * max_frames_per_request
        end = min(start + max_frames_per_request, total_sampled_frames)
        chunk_frames = all_frames_base64[start:end]

        content = [{"type": "text", "text": visual_prompt}]
        for frame in chunk_frames:
            content.append({"type": "image_url", "image_url": {"url": frame}})

        messages = [{"role": "user", "content": content}]

        response = client.chat.completions.create(
            model=model_name,
            messages=messages,
            max_tokens=1024,
            temperature=0.7,
        )
        visual_descriptions.append(response.choices[0].message.content.strip())

    # 6. Combine everything into final detailed report
    print("Generating combined audio + video summary report...")

    combine_prompt = f"""
You are analyzing a video that combines visual content and spoken audio.

Visual descriptions (from sampled frames):
{"\n\n---\n\n".join(visual_descriptions)}

Full spoken transcript (with approximate timestamps):
{timed_transcript}

Provide a detailed, chronological summary report of the entire video, integrating:
- What is seen (actions, people, objects, scenes, text on screen)
- What is said (dialogue, narration)
- Key events and their timing
- Overall context and meaning

Make it clear, structured, and comprehensive.
"""

    final_response = client.chat.completions.create(
        model=model_name,
        messages=[{"role": "user", "content": combine_prompt}],
        max_tokens=2048,
        temperature=0.5,
    )

    return final_response.choices[0].message.content.strip()


# ================ RUN EXAMPLE ================
if __name__ == "__main__":
    video_file = "C:/Users/h75378/Downloads/sample_1.mp4"  # Update path

    report = analyze_video_with_audio(
        video_file,
        visual_prompt="Describe the key events, actions, people, objects, and scene changes in chronological order.",
        seconds_per_frame=4.0  # Lower = more visual detail
    )

    print("\n" + "="*80)
    print("DETAILED VIDEO + AUDIO SUMMARY REPORT")
    print("="*80)
    print(report)
