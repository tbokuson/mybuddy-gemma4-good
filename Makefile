# MyBuddy public source Makefile
#
# xcodebuild は常に -quiet を付ける。

SCHEME      := MyBuddy
DESTINATION ?= platform=iOS Simulator,name=iPhone 17

.PHONY: help build test test-ui test-ui-e2e test-ollama-integration test-diary-quality test-e2e-diary-normal test-e2e-diary-custom test-e2e-diary

help:
	@echo "make build                  - シミュレータ向けビルド (quiet)"
	@echo "make test                   - MyBuddyTests のユニットテストを実行"
	@echo "make test-ui                - MyBuddyUITests の存在確認（既定では skip）"
	@echo "make test-ui-e2e            - MyBuddyUITests を実行 (要 Ollama)"
	@echo "make test-ollama-integration - Ollama 実LLM統合テストを実行"
	@echo "make test-diary-quality     - 日記品質ユニットテストのみ (要 Ollama)"
	@echo "make test-e2e-diary         - 人格別 E2E テスト (通常+カスタム、要 Ollama)"
	@echo "make test-e2e-diary-normal  - 通常人格 E2E テストのみ"
	@echo "make test-e2e-diary-custom  - カスタム人格 E2E テストのみ"

build:
	xcodebuild -scheme $(SCHEME) -destination '$(DESTINATION)' -quiet build

test:
	xcodebuild -scheme $(SCHEME) -destination '$(DESTINATION)' -quiet test \
		-only-testing:MyBuddyTests

test-ui:
	xcodebuild -scheme $(SCHEME) -destination '$(DESTINATION)' -quiet test \
		-only-testing:MyBuddyUITests

test-ui-e2e:
	MYBUDDY_RUN_UI_E2E_TESTS=1 xcodebuild -scheme $(SCHEME) -destination '$(DESTINATION)' -quiet test \
		-only-testing:MyBuddyUITests

test-ollama-integration:
	MYBUDDY_RUN_OLLAMA_TESTS=1 xcodebuild -scheme $(SCHEME) -destination '$(DESTINATION)' -quiet test \
		-only-testing:MyBuddyTests/OllamaServiceIntegrationTests

# 日記品質ユニットテストだけを走らせるショートカット。
# Ollama が起動していない場合は XCTSkip になるので安全。
test-diary-quality:
	MYBUDDY_RUN_OLLAMA_TESTS=1 xcodebuild -scheme $(SCHEME) -destination '$(DESTINATION)' -quiet test \
		-only-testing:MyBuddyTests/DiaryQualityTests \
		-only-testing:MyBuddyTests/DiaryQualityMetricsTests

# 人格別 E2E テスト: オンボーディング→会話→日記作成・更新→タグ確認
# 要 Ollama (gemma4:e2b)
test-e2e-diary: test-e2e-diary-normal test-e2e-diary-custom

test-e2e-diary-normal:
	xcodebuild build-for-testing -scheme $(SCHEME) -destination '$(DESTINATION)' -quiet
	xcodebuild test-without-building -scheme $(SCHEME) -destination '$(DESTINATION)' \
		-only-testing:'MyBuddyUITests/MyBuddyUITests/testE2ENormalPersonaOnboardingToDiary' \
		2>&1 | tee /tmp/mybuddy-e2e-normal.log \
		| grep -E '\[NORMAL\]|Test Case|passed|failed'

test-e2e-diary-custom:
	xcodebuild build-for-testing -scheme $(SCHEME) -destination '$(DESTINATION)' -quiet
	xcodebuild test-without-building -scheme $(SCHEME) -destination '$(DESTINATION)' \
		-only-testing:'MyBuddyUITests/MyBuddyUITests/testE2ECustomPersonaOnboardingToDiary' \
		2>&1 | tee /tmp/mybuddy-e2e-custom.log \
		| grep -E '\[CUSTOM\]|Test Case|passed|failed'
