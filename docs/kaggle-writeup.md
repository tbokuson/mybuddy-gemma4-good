# MyBuddy: An Offline Multimodal AI Diary Powered by Gemma 4

## Summary

MyBuddy is an iPhone diary app that turns small daily conversations and photos into private diary entries. It runs Gemma 4 E2B-it on device through llama.cpp, with multimodal image understanding via mmproj-F16 / mtmd / CLIP. After the initial model download, conversations, image understanding, diary generation, and storage happen locally on the user's device.

The goal is simple: lower the barrier to reflection without requiring people to send intimate memories, photos, or emotions to a cloud service.

## Problem

Many people want to keep a diary, but a blank page is hard to start from. This is especially true when people are tired, isolated, or living through small but emotionally meaningful moments that do not feel "important enough" to write down.

Cloud-based AI journaling can reduce friction, but it introduces a trust problem. A diary may contain private relationships, locations, photos, health-related feelings, work stress, and vulnerable thoughts. For many users, the safest diary is one that does not leave the device.

MyBuddy focuses on this gap: private, low-friction reflection that still works when the network is unavailable.

## Solution

MyBuddy gives the user a small AI buddy. Instead of asking the user to write a polished entry, the app starts from a short conversation:

- The user chats about what happened today.
- The user can attach a photo when words are hard to start with.
- Gemma 4 responds with short, gentle follow-up questions.
- When the user is ready, the conversation and photos become a diary entry.
- The user can edit the generated diary freely.

The app began as Japanese-first, because many personal journaling apps and AI demos assume English. For the Gemma 4 Good Hackathon, MyBuddy now includes English UI, onboarding, chat prompts, diary generation prompts, settings, and App Store-facing materials so English-speaking judges can understand and try the core experience.

## Why Gemma 4

Gemma 4 is a strong fit because MyBuddy needs local intelligence, not a remote chatbot. The app uses:

- Gemma 4 E2B-it Q4_K_M for short reflective conversations and diary generation
- llama.cpp for iOS local inference
- mmproj-F16 via mtmd / CLIP for image understanding
- Metal acceleration on high-memory devices when available

This lets MyBuddy demonstrate an important property of open models: useful AI can live close to the user, even when the data is personal and the network is unreliable.

## Technical Implementation

MyBuddy is built with SwiftUI and SwiftData. The local AI runtime loads GGUF models from the app's Application Support directory after the first setup flow.

The diary pipeline has two main stages:

1. Memo extraction: user messages are converted into factual notes and explicitly stated feelings.
2. Thinking diary generation: Gemma 4 turns those notes into a diary title, body, emotion tags, and a short buddy note.

A verification stage checks that generated diary text does not lose important named entities compared with the extracted notes. If the quality guard detects regression, the app preserves the existing diary instead of replacing it.

For image messages, MyBuddy lazy-loads the vision projection model only when needed. The app uses a multimodal prompt format with the media token placed in the user turn, so the model can respond to the image in the context of the conversation.

## Offline-First Privacy

MyBuddy's privacy model is centered on a clear boundary:

- The initial model download requires network access.
- After the model files are installed, chat, diary generation, image understanding, and storage run on device.
- User conversations, diary entries, and photos are not sent to a server for inference.
- The app can be demonstrated in Airplane Mode after initial setup.

This matters because diary data is not just "content." It can describe a user's relationships, routines, emotions, places, and private photos. MyBuddy treats that as local-first personal memory.

## Multimodal Journaling

Photos are often easier than words. A meal, a walk, a room, a gift, or a screenshot can become the first handle for reflection.

MyBuddy lets the user attach a photo to the conversation. Gemma 4 can describe what it sees softly, ask a short reflective question, and later include the image in the diary entry. This makes journaling less dependent on typing a complete story from scratch.

## Impact

MyBuddy is not a medical app, therapy app, or diagnostic tool. Its impact is more modest and practical: it helps people keep a private reflective habit with less friction.

The social value comes from three ideas:

- Digital equity: reflection support should still work when connectivity is limited.
- Safety and trust: intimate diary data should not have to leave the device.
- Inclusion: Japanese-first users and non-English personal contexts deserve high-quality AI experiences too.

For people who feel blocked by a blank page, a small private conversation can be enough to preserve a day that would otherwise disappear.

## Limitations / Future Work

MyBuddy currently requires a large initial model download. Local inference performance depends on device memory and hardware. The English experience is now available across the core app flow, but deeper localization and broader real-world English QA are still ongoing.

Future work includes deeper localization, better long-term memory controls, accessibility improvements, export options, and clearer user-facing explanations of the local AI runtime.

## Links

- Demo video: https://www.youtube.com/watch?v=aNzIq4aFZ3E
- Public GitHub repository: https://github.com/tbokuson/mybuddy-gemma4-good
- Privacy Policy: https://mybuddy.4koma-news.com/privacy/
- Terms of Service: https://mybuddy.4koma-news.com/terms/
- Support: https://mybuddy.4koma-news.com/support/

The App Store link will be added to the Kaggle attachments when the public App Store page is available. The current submission includes the demo video, public source repository, and public privacy/support pages so judges can understand the project and its privacy model.
