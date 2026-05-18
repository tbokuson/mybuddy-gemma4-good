# Kaggle Submission Draft

## Project Title

MyBuddy: A Private Multimodal AI Diary Powered by Gemma 4

## Short Summary

MyBuddy is an iPhone diary app that turns casual conversations and photos into private diary entries. It runs Gemma 4 locally on the user's iPhone through llama.cpp, with multimodal image understanding via mmproj-F16 / mtmd / CLIP. After the initial model download, chats, photos, image understanding, diary generation, and storage stay on device.

## One-Line Pitch

A private AI buddy that helps people turn ordinary daily moments and photos into diary entries, without sending personal memories to the cloud.

## Problem

Many people want to keep a diary, but starting from a blank page is hard. The barrier is even higher when someone is tired, isolated, or unsure whether a small moment is worth writing down. Cloud AI can make journaling easier, but a diary often includes private photos, emotions, routines, places, and relationships. MyBuddy explores a more private path: low-friction reflection powered by local AI.

## Solution

MyBuddy starts with a personal AI buddy instead of a blank editor. The user can customize the buddy's look and personality, chat casually about the day, attach a photo, and generate an editable diary entry. The product goal is not to replace human support or provide therapy. It is to make private reflection easier to continue.

## How Gemma 4 Is Used

- Gemma 4 E2B-it Q4_K_M for chat and diary generation
- llama.cpp for local iOS inference
- mmproj-F16 / mtmd / CLIP for image understanding
- Multimodal prompts for text-and-image conversation
- Local diary generation from extracted conversation notes and selected photos

## Privacy / Offline Behavior

MyBuddy requires network access for the initial model download. After setup, the core experience runs locally on the iPhone. Conversations, diary entries, photos, buddy settings, and generated diary content are not sent to a server for AI inference.

## Demo Video

Local file:

```text
tmp/exports/mybuddy-gemma4-good-hackathon-demo.mp4
```

Video specs:

- Duration: 75.5 seconds
- Resolution: 1320 x 2868
- Size: about 57 MB
- Format: MP4

## Card / Thumbnail Image

Use this image for the Kaggle card and thumbnail upload:

```text
media/mybuddy-kaggle-card-560x280.png
```

Image specs:

- Resolution: 560 x 280
- Format: PNG

YouTube URL:

```text
https://www.youtube.com/watch?v=aNzIq4aFZ3E
```

## Live Demo Instructions

Use the App Store build on a compatible iPhone. The first launch downloads large AI model files, so Wi-Fi is recommended. After the initial download completes, the app can be tested offline for chat, photo-based reflection, diary generation, and diary browsing.

App Store URL:

```text
To be added when the App Store public page is available.
```

## Public Repository

Use the public source repository prepared for the hackathon submission.

Repository URL:

```text
https://github.com/tbokuson/mybuddy-gemma4-good
```

Included contents:

- Real SwiftUI app source
- Local Gemma 4 runtime integration
- Multimodal image understanding bridge
- Diary pipeline and prompt builders
- Unit/UI test targets
- Kaggle writeup, privacy architecture, demo script, and screenshots

## Media Gallery Captions

1. Create a personal AI buddy with a custom look, tone, and conversational distance.
2. Start journaling from a small daily chat instead of a blank page.
3. Attach a photo so Gemma 4 can reflect on text and images together.
4. Generate an editable diary entry from the conversation and photo.
5. Keep entries organized as a private on-device diary archive.

## Claims to Avoid

- Do not describe MyBuddy as therapy.
- Do not claim it treats loneliness, anxiety, depression, or any medical condition.
- Do not imply emergency, crisis, legal, financial, or medical advice.
- Do not imply user data is uploaded for inference.
