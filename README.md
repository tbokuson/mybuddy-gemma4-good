# MyBuddy

**MyBuddy is an offline-first multimodal AI diary for iPhone, powered by Gemma 4.**

It turns small daily conversations and photos into private diary entries. The app runs local inference on device through `llama.cpp`, uses Gemma 4 E2B-it for chat and diary generation, and uses `mmproj-F16` with `mtmd` / CLIP for image understanding.

This repository is the public source package for the Gemma 4 Good Hackathon submission. It contains the real SwiftUI app implementation, tests, prompt builders, diary pipeline, model delivery flow, and local multimodal runtime integration. It excludes only local development artifacts, private credentials, generated build outputs, and large GGUF model files.

## Submission Links

- Demo video: https://www.youtube.com/watch?v=aNzIq4aFZ3E
- Privacy Policy: https://mybuddy.4koma-news.com/privacy/
- Terms of Service: https://mybuddy.4koma-news.com/terms/
- Support: https://mybuddy.4koma-news.com/support/
- Kaggle writeup: `docs/kaggle-writeup.md`

## What It Does

- Lets the user chat with a customizable AI buddy.
- Supports Japanese and English UI, onboarding, chat prompts, and diary generation prompts.
- Accepts photo messages so the user can start reflection from an image instead of a blank page.
- Generates a diary entry from the conversation and attached photos.
- Stores conversations, diary entries, images, and profile data on device.
- Runs without sending diary content, photos, or conversations to a remote inference server after setup.

MyBuddy is not a medical, therapy, legal, or financial advice app. It is a private journaling tool designed to lower the friction of everyday reflection.

## Tech Stack

| Layer | Technology |
| --- | --- |
| App | SwiftUI |
| Persistence | SwiftData |
| Text model | Gemma 4 E2B-it Q4_K_M GGUF |
| Runtime | llama.cpp via `Vendor/llama.xcframework` |
| Vision | `mmproj-F16.gguf` via `mtmd` / CLIP |
| Acceleration | Metal on high-memory devices |
| Tests | XCTest / XCUITest |

## Repository Layout

```text
MyBuddy/
  Models/                 SwiftData models
  Services/               LLM runtime, prompts, diary pipeline, model delivery
  ViewModels/             App state and screen logic
  Views/                  SwiftUI screens and components
  VisionEngine/           mtmd / CLIP bridge sources
MyBuddyTests/             Unit and integration-style tests
MyBuddyUITests/           UI test target
Vendor/llama.xcframework  Local llama.cpp runtime binary
docs/                     Kaggle, privacy, and demo documentation
media/                    Submission thumbnail and screenshots
```

## Model Files

Large model files are not committed to this repository:

```text
gemma-4-E2B-it-Q4_K_M.gguf
mmproj-F16.gguf
```

The production App Store build downloads them during first setup using the bundled model delivery manifest:

```text
MyBuddy/Support/ModelDeliveryManifest.plist
```

The public repository does not include the production model CDN endpoint. To run the app from source, configure `chunkBaseURLString` in the manifest for your own model distribution endpoint, or place the GGUF files in one of the app's supported local model locations:

- `Application Support/Models/`
- the app bundle during development
- the legacy `Documents/` location

After the model files are installed, chat, image understanding, diary generation, and storage run locally on device.

## Build

Open `MyBuddy.xcodeproj` in Xcode and run the `MyBuddy` scheme on an iPhone or simulator.

The project also includes Make targets used during development:

```bash
make build
make test
```

If your simulator name differs, override the destination:

```bash
make build DESTINATION="platform=iOS Simulator,name=iPhone 17"
```

Local LLM inference is intended for real iPhone hardware. Simulator builds are useful for UI and unit-test verification, but local model performance is not representative.

## Privacy Architecture

MyBuddy uses a local-first boundary:

1. The initial setup downloads large model files.
2. The app verifies and stores the models on device.
3. Conversations, diary generation, photo understanding, and storage happen locally.
4. User diary data and photos are not sent to a cloud inference API.

See `docs/privacy-architecture.md` for the submission-facing explanation.

## Kaggle Materials

- `docs/kaggle-writeup.md`: writeup draft used for the Kaggle project page.
- `docs/demo-script.md`: video structure and caption plan.
- `docs/kaggle-submission-draft.md`: project-page copy and attachment notes.
- `docs/youtube-description.md`: YouTube description draft.
- `media/`: thumbnail and screenshots for the Kaggle media gallery.

## License And Model Notes

The app source is provided for hackathon review and reproducibility. Gemma model usage is subject to the applicable Gemma terms and model distribution requirements. The GGUF model weights are intentionally not stored in this Git repository because of size and distribution constraints.
