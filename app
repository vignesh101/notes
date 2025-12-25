def analyze_video_chunked(video_path, prompt="Describe what is happening in this video in detail.", max_frames_per_request=8, total_frames=24):
    """
    Extract more frames (e.g., 24) and send them in chunks of 8 to the model.
    Then combine all responses.
    """
    import math
    
    # Calculate how many chunks we need
    chunks = math.ceil(total_frames / max_frames_per_request)
    all_analyses = []

    print(f"Extracting {total_frames} frames in {chunks} chunk(s) of up to {max_frames_per_request}...")

    for chunk_idx in range(chunks):
        start_frame = chunk_idx * max_frames_per_request
        end_frame = min((chunk_idx + 1) * max_frames_per_request, total_frames)
        num_in_chunk = end_frame - start_frame
        
        print(f"Processing chunk {chunk_idx + 1}/{chunks}: frames {start_frame+1}–{end_frame}")

        # Extract only this chunk's worth of evenly spaced frames
        frames_base64 = extract_frames_from_video(video_path, num_frames=num_in_chunk)
        
        # Adjust spacing to cover the full video evenly across all chunks
        # (Alternatively, you could sample different sections per chunk)

        content = [{"type": "text", "text": f"{prompt} (Part {chunk_idx + 1}/{chunks})"}]
        for frame in frames_base64:
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

        part_analysis = response.choices[0].message.content
        all_analyses.append(part_analysis)
        print(f"Chunk {chunk_idx + 1} complete.\n")

    # Optional: Final summary combining all parts
    final_prompt = "Combine these partial video descriptions into one coherent summary of the entire video:\n\n" + "\n\n".join(
        [f"Part {i+1}: {text}" for i, text in enumerate(all_analyses)]
    )

    final_response = client.chat.completions.create(
        model=model_name,
        messages=[{"role": "user", "content": final_prompt}],
        max_tokens=1024,
    )

    full_summary = final_response.choices[0].message.content
    return "\n\n".join(all_analyses) + "\n\n--- FINAL SUMMARY ---\n" + full_summary


if __name__ == "__main__":
    video_file = "C:/Users/h75378/Downloads/sample_1.mp4"
    result = analyze_video_chunked(
        video_file,
        prompt="Describe the actions, people, and events shown step by step.",
        max_frames_per_request=8,
        total_frames=24  # e.g., 3 chunks of 8 frames → better coverage
    )
    print("\nFull Video Analysis (Chunked):\n")
    print(result)
