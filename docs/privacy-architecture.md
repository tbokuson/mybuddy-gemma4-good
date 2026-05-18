# Privacy and Offline Architecture

## Core Boundary

MyBuddy is designed around a simple privacy boundary:

- Network access is needed for the initial model download.
- After model setup, AI inference runs on the user's iPhone.
- Conversations, diary entries, and photos are stored locally.
- User diary data is not sent to a remote inference API.

## Model Files

Release builds download the required GGUF model files during initial setup and store them under the app's Application Support directory.

| File | Purpose |
| --- | --- |
| `gemma-4-E2B-it-Q4_K_M.gguf` | Text conversation and diary generation |
| `mmproj-F16.gguf` | Vision projection for image understanding |

The app can resume interrupted downloads by reusing completed chunks. The model download request does not include user conversations, diary entries, or photos.

## Local Inference

MyBuddy uses llama.cpp on iOS to run Gemma 4 locally. For multimodal messages, the vision projection model is loaded lazily when the user attaches an image.

The app performs:

- Chat response generation
- Image-aware response generation
- Memo extraction from user messages
- Diary title/body/tag generation
- Buddy note generation

on device after setup.

## Local Storage

SwiftData stores app data on device, including:

- Buddy profile
- Chat sessions and messages
- Diary entries
- Diary notes
- Images attached to diary entries

The submission demo should use non-sensitive sample data only.

## What MyBuddy Does Not Claim

MyBuddy is not a medical device, therapy product, diagnostic tool, or crisis service. It is a private journaling and reflection app. The app should not be presented as treating loneliness, depression, anxiety, or any medical condition.

## Demo Proof Point

For the Kaggle demo, show the app working in Airplane Mode after the initial model download. This demonstrates the offline boundary clearly without overclaiming.
