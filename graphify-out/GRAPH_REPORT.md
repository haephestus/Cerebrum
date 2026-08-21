# Graph Report - /run/media/harbinger/nixfiles/projects/Cerebrum  (2026-08-21)

## Corpus Check
- cluster-only mode — file stats not available

## Summary
- 1792 nodes · 2199 edges · 131 communities (82 shown, 49 thin omitted)
- Extraction: 99% EXTRACTED · 1% INFERRED · 0% AMBIGUOUS · INFERRED: 24 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `350c1faa`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- Cross-Repo Contracts
- radial_tool_dial.dart
- app_database.dart
- Win32Window
- editor_scaffold.dart
- engram_models.dart
- editor_settings_store.dart
- d_learning_center_page.dart
- appflowy_text_driver.dart
- paged_note_controller.dart
- ollama_settings.dart
- GeneratedPluginRegistrant.swift
- note_store.dart
- page_surface.dart
- upcoming_engrams.dart
- engram_attempt_store.dart
- drawing_layer.dart
- sync_service.dart
- study_plan_detail_page.dart
- code_block_component.dart
- my_application.cc
- offline_mastery.dart
- analysis_mode_controller.dart
- bubbles_api.dart
- editor_commands.dart
- long_questions.dart
- d_study_bubble_page.dart
- user_session.dart
- mcq.dart
- flashcard.dart
- short_question.dart
- login_screen.dart
- paged_editor.dart
- ai_block_component.dart
- engram_sync_service.dart
- note_image_resolver.dart
- vim_move_controller.dart
- file_library.dart
- main.dart
- api_config.dart
- connection_settings.dart
- desktop_main.dart
- learning_center_api.dart
- State
- user_api.dart
- Tool Wheel Plan
- text_editing_driver.dart
- note_editor_controller.dart
- study_bubbles_summary.dart
- id.dart
- settings.dart
- configs_api.dart
- StatelessWidget
- wWinMain
- d_study_bubble_home.dart
- package:flutter/material.dart
- planner_api.dart
- notifications.dart
- dart:convert
- sidebar_button.dart
- List
- study_plan_api.dart
- editable_title.dart
- manifest.json
- engram_store.dart
- knowledgebase_api.dart
- CachedEngram
- d_homescreen_page.dart
- sync_api.dart
- editor_surface.dart
- Map
- MaterialPageRoute
- package:flutter/foundation.dart
- erase_split_test.dart
- VoidCallback
- responsive_layout.dart
- EditorState
- EngramAttempts
- BlockComponentBuilder
- AppDatabase
- Color
- _RenderDiscHit
- _DiscHitRegion
- PageSurface
- start.sh
- String?
- attemptId
- bubbleId
- contentJson
- createdAt
- dueAt
- easeFactor
- engramId
- error
- id
- intervalDays
- jobId
- lapses
- lastGrade
- masteryState
- noteId
- payloadJson
- repetitions
- resultJson
- seen
- status
- tagsJson
- targetCognitiveLevel
- type
- updatedAt
- userId
- Phase 0 Foundation
- _DLearningCenterPageState
- EditorScaffold
- _CreateStudyPlanDialog
- Changelog 2026-08-06
- Changelog 2026-08-08
- Changelog 2026-08-09
- Changelog 2026-08-10
- Changelog 2026-08-11
- Tombstone
- Version Vectors
- Flutter Frontend
- Flutter Screenshot
- Architecture Decisions
- Plan Core Feature
- Plan Features
- Plan Foundation
- Plan Hardening
- Plan Ship

## God Nodes (most connected - your core abstractions)
1. `Win32Window` - 22 edges
2. `MessageHandler` - 12 edges
3. `FlutterWindow` - 10 edges
4. `Create` - 10 edges
5. `WndProc` - 10 edges
6. `MessageHandler` - 9 edges
7. `Cross-Repo Contracts` - 9 edges
8. `OnCreate` - 7 edges
9. `WindowClassRegistrar` - 7 edges
10. `Destroy` - 7 edges

## Surprising Connections (you probably didn't know these)
- `Cerebrum` --conceptually_related_to--> `Offline-First Plan`  [INFERRED]
  README.md → docs/offline-first-plan.md
- `Drift Migration` --references--> `SQLite`  [EXTRACTED]
  docs/drift-migration.md → README.md
- `wWinMain()` --calls--> `CreateAndAttachConsole()`  [INFERRED]
  src/windows/runner/main.cpp → src/windows/runner/utils.cpp
- `Win32Window::Win32Window()` --calls--> `Destroy`  [INFERRED]
  src/windows/runner/win32_window.cpp → src/windows/runner/win32_window.h
- `Cerebrum` --references--> `Cross-Repo Contracts`  [EXTRACTED]
  README.md → docs/cross-repo-contracts.md

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Offline-First Architecture Pattern** — docs_offline_first_plan_notestore, docs_offline_first_plan_syncservice_outbox, docs_offline_first_plan_client_owned_note_id, docs_offline_first_plan_image_ref_resolver, docs_offline_first_plan_last_writer_wins [EXTRACTED 0.90]
- **Client-Daemon Sync Contracts** — docs_cross_repo_contracts_note_sync_contract, docs_cross_repo_contracts_engram_submit_contract, docs_cross_repo_contracts_mastery_contract, docs_cross_repo_contracts_grading_job_contract, docs_cross_repo_contracts_attempt_dedup_contract [EXTRACTED 0.90]

## Communities (131 total, 49 thin omitted)

### Community -1 - "Cross-Repo Contracts"
Cohesion: 0.07
Nodes (34): Attempt Dedup Contract, Cross-Repo Contracts, Engram Submit Contract, Grading Job Contract, Identity Contract, Image Ref Contract, Mastery Contract, Note Sync Contract (+26 more)

### Community 0 - "radial_tool_dial.dart"
Cohesion: 0.01
Nodes (135): Color get, double?, EditorSettings get, package:flutter/rendering.dart, return, ../../../services/editor_settings_store.dart, _accent, _activeTheme (+127 more)

### Community 1 - "app_database.dart"
Cohesion: 0.02
Nodes (102): BoolColumn get, class EngramAttemptRow extends, class EngramMasteryRow extends, ColumnFilters, ColumnOrderings, DateTimeColumn get, GeneratedColumn, GeneratedDatabase (+94 more)

### Community 2 - "Win32Window"
Cohesion: 0.06
Nodes (53): PluginRegistry, Point, RECT, Size, RegisterPlugins(), DartProject, HWND, LPARAM (+45 more)

### Community 3 - "editor_scaffold.dart"
Cohesion: 0.03
Nodes (58): package:cerebrum/ui/editor/controllers/analysis_mode_controller.dart, package:cerebrum/ui/editor/screens/radial_tool_dial.dart, package:gpt_markdown/gpt_markdown.dart, _analysisChunks, _analysisData, _analysisEnabled, _analysisMode, _analysisModeBar (+50 more)

### Community 4 - "engram_models.dart"
Cohesion: 0.05
Nodes (45): answer, back, bridgeConcept, bubbleId, cardNumber, content, contextAnchored, correctOption (+37 more)

### Community 5 - "editor_settings_store.dart"
Cohesion: 0.05
Nodes (40): addCustomColor, arrangeIntoWheel, builtIn, builtIns, color, copyWith, CustomSwatch, _editorDir (+32 more)

### Community 6 - "d_learning_center_page.dart"
Cohesion: 0.05
Nodes (37): package:cerebrum/ui/screens/learning_center/engrams/completion/flashcard.dart, package:cerebrum/ui/screens/learning_center/engrams/completion/long_questions.dart, package:cerebrum/ui/screens/learning_center/engrams/completion/mcq.dart, package:cerebrum/ui/screens/learning_center/engrams/completion/short_question.dart, package:cerebrum/ui/screens/learning_center/study_plan_detail_page.dart, bubbleId, build, _buildEngramsTab (+29 more)

### Community 7 - "appflowy_text_driver.dart"
Cohesion: 0.06
Nodes (35): class AppFlowyTextDriver extends, EditorScrollController, Listenable get, package:cerebrum/ui/editor/blocks/ai_block/ai_block_component.dart, package:cerebrum/ui/editor/blocks/code_block/code_block_component.dart, package:cerebrum/ui/editor/helpers/editor_commands.dart, _aiBlockMenuItem, _autoFocus (+27 more)

### Community 8 - "paged_note_controller.dart"
Cohesion: 0.06
Nodes (35): NoteEditorController get, PageLayoutMode get, activeController, _activeIndex, addPage, applyDrawingTool, _applyVimState, controller (+27 more)

### Community 9 - "ollama_settings.dart"
Cohesion: 0.06
Nodes (31): package:cerebrum/api/configs_api.dart, build, _buildModelDropdown, chatInstalledExpanded, chatOnlineExpanded, chatSearchQuery, checkingStatus, checkOllamaStatus (+23 more)

### Community 10 - "GeneratedPluginRegistrant.swift"
Cohesion: 0.07
Nodes (26): Bool, Cocoa, device_info_plus, file_picker, flutter_secure_storage_darwin, FlutterAppDelegate, FlutterMacOS, FlutterPluginRegistry (+18 more)

### Community 11 - "note_store.dart"
Cohesion: 0.06
Nodes (33): dart:io, dart:typed_data, package:path_provider/path_provider.dart, _cerebrumRoot, clearDirty, imageBytes, imageDaemonUrls, _imageManifest (+25 more)

### Community 12 - "page_surface.dart"
Cohesion: 0.06
Nodes (32): GlobalKey, int?, package:cerebrum/ui/editor/controllers/appflowy_text_driver.dart, package:cerebrum/ui/editor/screens/paged_editor.dart, _activeBlockIndex, _activeChunks, analysisForBlock, _analysisOverlay (+24 more)

### Community 13 - "upcoming_engrams.dart"
Cohesion: 0.07
Nodes (28): build, chipColor, color, createState, date, _days, DaySchedule, didChangeAppLifecycleState (+20 more)

### Community 14 - "engram_attempt_store.dart"
Cohesion: 0.06
Nodes (30): attemptId, createdAt, _db, EngramAttemptStore, engramId, error, fromJson, _fromRow (+22 more)

### Community 15 - "drawing_layer.dart"
Cohesion: 0.07
Nodes (28): CustomPainter, double get, EagerGestureRecognizer, Offset?, package:flutter/gestures.dart, Sketch?, _begin, build (+20 more)

### Community 16 - "sync_service.dart"
Cohesion: 0.07
Nodes (28): _deleteOutbox, _dequeue, _dequeueDelete, _dequeueImage, _drainDeletes, _drainImages, drainOutbox, _enqueue (+20 more)

### Community 17 - "study_plan_detail_page.dart"
Cohesion: 0.05
Nodes (38): Future, package:cerebrum/api/planner_api.dart, package:cerebrum/ui/desktop_main.dart, package:cerebrum/ui/screens/onboarding/login_screen.dart, package:cerebrum/ui/screens/onboarding/onboarding_screen.dart, AppEntryPoint, _AppEntryPointState, build (+30 more)

### Community 18 - "code_block_component.dart"
Cohesion: 0.08
Nodes (24): BlockComponentContext, EdgeInsets, package:flutter_highlight/flutter_highlight.dart, package:flutter_highlight/themes/atom-one-dark.dart, package:flutter/services.dart, blockComponentContext, build, codeBlockNode (+16 more)

### Community 19 - "my_application.cc"
Cohesion: 0.10
Nodes (20): FlPluginRegistry, GApplication, gboolean, gchar, GObject, GtkApplication, MyApplicationClass, fl_register_plugins() (+12 more)

### Community 20 - "offline_mastery.dart"
Cohesion: 0.08
Nodes (23): adoptServerState, applyFlashcard, applyMcq, _applySm2, _db, dueAt, easeFactor, engramId (+15 more)

### Community 21 - "analysis_mode_controller.dart"
Cohesion: 0.09
Nodes (22): AnalysisChunkRef? get, @immutable, int get, AnalysisChunkRef, blockIds, chunk, chunkId, _chunks (+14 more)

### Community 22 - "bubbles_api.dart"
Cohesion: 0.09
Nodes (22): baseUrl, BubbleChatApi, BubbleNotesApi, BubblesApi, bubblesEndpoint, chatApi, clearChatHistory, createBubble (+14 more)

### Community 23 - "editor_commands.dart"
Cohesion: 0.09
Nodes (22): _allPrintable, _alreadyMapped, _duplicateLineHandler, _duplicateLineShortcut, EditorShortcuts, _escapeHandler, _escapeToNormalModeShortcut, getCharacterShortcuts (+14 more)

### Community 24 - "long_questions.dart"
Cohesion: 0.11
Nodes (19): class, _answerAgain, _attempt, build, _buildForm, _buildModelAnswer, _controller, createState (+11 more)

### Community 25 - "d_study_bubble_page.dart"
Cohesion: 0.10
Nodes (21): package:cerebrum/ui/editor/blocks/image/note_image_resolver.dart, package:cerebrum/ui/editor/editor_scaffold.dart, package:cerebrum/ui/widgets/editable_title.dart, addMode, bubble, bubbleId, build, createBubble (+13 more)

### Community 26 - "user_session.dart"
Cohesion: 0.09
Nodes (21): package:flutter_secure_storage/flutter_secure_storage.dart, clear, getDaemonKey, getEmail, getToken, getUserId, getUsername, hasSeenOnboarding (+13 more)

### Community 27 - "mcq.dart"
Cohesion: 0.10
Nodes (20): McqContent get, package:cerebrum/services/offline_mastery.dart, _attempt, build, _content, createState, engram, initState (+12 more)

### Community 28 - "flashcard.dart"
Cohesion: 0.10
Nodes (20): package:cerebrum/services/engram_attempt_store.dart, MasteryRecord, _attempt, build, createState, engram, FlashcardCompletionPage, _FlashcardCompletionPageState (+12 more)

### Community 29 - "short_question.dart"
Cohesion: 0.10
Nodes (20): EngramAttempt, _answerAgain, _attempt, _AttemptStatus, build, _buildComparison, _controllerFor, _controllers (+12 more)

### Community 30 - "login_screen.dart"
Cohesion: 0.11
Nodes (18): FormState, package:cerebrum/api/user_api.dart, build, createState, dispose, _emailController, _errorMessage, _formKey (+10 more)

### Community 31 - "paged_editor.dart"
Cohesion: 0.11
Nodes (18): package:cerebrum/ui/editor/controllers/paged_note_controller.dart, package:cerebrum/ui/editor/screens/page_surface.dart, PageController, _AddPageTile, analysisForBlock, BlockAnalysisLookup, build, controller (+10 more)

### Community 32 - "ai_block_component.dart"
Cohesion: 0.11
Nodes (17): BlockComponentValidate get, EditorState get, Node get, package:appflowy_editor/appflowy_editor.dart, package:provider/provider.dart, aiBlockNode, build, createState (+9 more)

### Community 33 - "engram_sync_service.dart"
Cohesion: 0.11
Nodes (17): dart:async, package:cerebrum/api/learning_center_api.dart, package:cerebrum/services/id.dart, package:cerebrum/services/notifications.dart, _advance, drain, EngramSyncService, _ensureAutoDrain (+9 more)

### Community 34 - "note_image_resolver.dart"
Cohesion: 0.11
Nodes (17): package:cerebrum/services/note_store.dart, configureForNote, _daemonUrls, _imagesDirPath, isRef, _localNames, makeRef, mapDocumentUrls (+9 more)

### Community 35 - "vim_move_controller.dart"
Cohesion: 0.12
Nodes (16): bool get, DateTime, enterAnalysisMode, enterInsertMode, enterNormalMode, isAnalysis, _isEnabled, isInsert (+8 more)

### Community 36 - "file_library.dart"
Cohesion: 0.12
Nodes (16): package:cerebrum/api/knowledgebase_api.dart, build, _buildRegistry, _confirmDelete, createState, _deleteFile, FileLibrary, _FileLibraryState (+8 more)

### Community 37 - "main.dart"
Cohesion: 0.13
Nodes (14): package:cerebrum/services/engram_sync_service.dart, package:cerebrum/services/sync_service.dart, package:window_manager/window_manager.dart, build, createState, didChangeAppLifecycleState, dispose, ensureInitialized (+6 more)

### Community 38 - "api_config.dart"
Cohesion: 0.12
Nodes (16): package:shared_preferences/shared_preferences.dart, ApiConfig, baseUrl, _defaultCloudUrl, _defaultLocalUrl, headers, init, _keyCloudUrl (+8 more)

### Community 39 - "connection_settings.dart"
Cohesion: 0.12
Nodes (16): DeploymentMode, build, _cloudUrlController, ConnectionSettings, _ConnectionSettingsState, createState, _daemonKeyController, dispose (+8 more)

### Community 40 - "desktop_main.dart"
Cohesion: 0.13
Nodes (15): package:cerebrum/ui/screens/home/d_homescreen_page.dart, package:cerebrum/ui/screens/learning_center/d_learning_center_page.dart, package:cerebrum/ui/screens/settings/settings.dart, package:cerebrum/ui/screens/study_bubble/d_study_bubble_home.dart, package:cerebrum/ui/widgets/sidebar_button.dart, build, _buildPage, changePage (+7 more)

### Community 41 - "learning_center_api.dart"
Cohesion: 0.13
Nodes (14): package:cerebrum/models/engram_models.dart, package:cerebrum/services/engram_store.dart, baseUrl, fetchGradingJob, getAnalysisStatus, getFullCachedAnalysis, LearningCenterApi, learningCenterEndpoint (+6 more)

### Community 42 - "State"
Cohesion: 0.17
Nodes (17): CerebrumApp, _CerebrumAppState, _CustomColorDialog, _CustomColorDialogState, _ThemeEditorDialog, _ThemeEditorDialogState, ToolDialHub, _ToolDialHubState (+9 more)

### Community 43 - "user_api.dart"
Cohesion: 0.15
Nodes (13): Exception, AccountAlreadyExistsException, baseUrl, createAccount, deleteAccount, email, fetchCurrentUser, InvalidCredentialsException (+5 more)

### Community 44 - "Tool Wheel Plan"
Cohesion: 0.33
Nodes (6): Colour Wheel, Concentric Ring Wheel, Size Ring, Tool Ring, Tool Wheel Plan, ToolDialHub

### Community 45 - "text_editing_driver.dart"
Cohesion: 0.16
Nodes (13): package:cerebrum/ui/editor/controllers/vim_move_controller.dart, package:flutter/widgets.dart, AnalysisModeController, AppFlowyTextDriver, ChangeNotifier, NoteEditorController, PagedNoteController, buildEditor (+5 more)

### Community 46 - "note_editor_controller.dart"
Cohesion: 0.14
Nodes (13): ScribbleNotifier, ScribbleNotifier get, dispose, documentJson, _drawingEnabled, _drawingNotifier, _driver, inkJson (+5 more)

### Community 47 - "study_bubbles_summary.dart"
Cohesion: 0.15
Nodes (13): _bubbles, build, createState, _error, _fetch, initState, _loading, maxPreview (+5 more)

### Community 48 - "id.dart"
Cohesion: 0.15
Nodes (12): dart:math, package:crypto/crypto.dart, bubbleIdFromName, bytes, _crockford, generate, map, nanoid (+4 more)

### Community 49 - "settings.dart"
Cohesion: 0.17
Nodes (12): package:cerebrum/ui/screens/settings/connection_settings.dart, package:cerebrum/ui/screens/settings/ollama_settings.dart, package:cerebrum/ui/widgets/debug_reset_button.dart, package:cerebrum/ui/widgets/floating_modal.dart, build, _buildPage, changePage, createState (+4 more)

### Community 50 - "configs_api.dart"
Cohesion: 0.15
Nodes (12): baseUrl, ConfigsApi, configsEndpoint, downloadModel, fetchConfigs, fetchInstalledChatModels, fetchInstalledEmbeddingModels, fetchModelDetails (+4 more)

### Community 51 - "StatelessWidget"
Cohesion: 0.14
Nodes (14): _CodeBlockHeader, _HeadingIcon, _ChunkExpansionTile, _FindingTile, NoteDrawingLayer, _AnalysisPopover, _HexToggle, DayEngramsCard (+6 more)

### Community 52 - "wWinMain"
Cohesion: 0.24
Nodes (9): _In_, _In_opt_, wWinMain(), string, wchar_t, CreateAndAttachConsole(), GetCommandLineArguments(), Utf8FromUtf16() (+1 more)

### Community 53 - "d_study_bubble_home.dart"
Cohesion: 0.18
Nodes (11): package:cerebrum/api/bubbles_api.dart, package:cerebrum/ui/screens/study_bubble/d_study_bubble_page.dart, package:cerebrum/ui/widgets/card_view.dart, bubbles, build, createState, deleteBubbles, DStudyBubbleHome (+3 more)

### Community 54 - "package:flutter/material.dart"
Cohesion: 0.25
Nodes (5): package:flutter/material.dart, build, Notes, build, SuggestedReading

### Community 55 - "planner_api.dart"
Cohesion: 0.17
Nodes (11): activePlan, baseUrl, completeTask, densifyPhase, generatePlan, getPlans, getProgress, PlannerApi (+3 more)

### Community 56 - "notifications.dart"
Cohesion: 0.18
Nodes (11): badgeCount, LoggingNotificationSink, Notifications, NotificationSink, notify, refreshBadge, setBadge, show (+3 more)

### Community 57 - "dart:convert"
Cohesion: 0.20
Nodes (9): api_config.dart, dart:convert, package:http/http.dart, baseUrl, Reading, readingEndpoint, askRose, response (+1 more)

### Community 58 - "sidebar_button.dart"
Cohesion: 0.20
Nodes (10): IconData, build, createState, _hovering, icon, label, onPressed, selected (+2 more)

### Community 59 - "List"
Cohesion: 0.18
Nodes (10): List, actions, build, child, FloatingModal, heightFactor, onClose, showCloseButton (+2 more)

### Community 60 - "study_plan_api.dart"
Cohesion: 0.18
Nodes (10): achieveMetric, baseUrl, completePhase, getActivePlans, getIncompletePhases, getPlan, getUnachievedMetrics, requestPlan (+2 more)

### Community 61 - "editable_title.dart"
Cohesion: 0.20
Nodes (10): build, controller, createState, dispose, EditableTitle, __EditableTitleState, initialTitle, initState (+2 more)

### Community 62 - "manifest.json"
Cohesion: 0.18
Nodes (10): background_color, description, display, icons, name, orientation, prefer_related_applications, short_name (+2 more)

### Community 63 - "engram_store.dart"
Cohesion: 0.20
Nodes (9): package:cerebrum/services/db/app_database.dart, package:drift/drift.dart, Engram, cachedResponse, cacheRaw, _db, EngramStore, _rowToEngram (+1 more)

### Community 64 - "knowledgebase_api.dart"
Cohesion: 0.20
Nodes (9): package:file_picker/file_picker.dart, baseUrl, deleteFiles, KnowledgebaseApi, knowledgebaseEndpoint, pickFile, processFile, showFiles (+1 more)

### Community 65 - "CachedEngram"
Cohesion: 0.33
Nodes (9): Insertable, CachedEngram, CachedEngramsCompanion, DataClass, EngramAttemptRow, EngramAttemptsCompanion, EngramMasteryRow, EngramMasteryRowsCompanion (+1 more)

### Community 66 - "d_homescreen_page.dart"
Cohesion: 0.25
Nodes (8): package:cerebrum/ui/screens/home/file_library.dart, package:cerebrum/ui/screens/home/notes.dart, package:cerebrum/ui/screens/home/suggested_reading.dart, package:cerebrum/ui/screens/home/upcoming_engrams.dart, build, createState, DHomescreen, _DHomescreenState

### Community 67 - "sync_api.dart"
Cohesion: 0.25
Nodes (7): package:cerebrum/api/api_config.dart, baseUrl, pull, push, replicaId, SyncApi, static String get

### Community 68 - "editor_surface.dart"
Cohesion: 0.25
Nodes (7): package:cerebrum/ui/editor/controllers/note_editor_controller.dart, package:cerebrum/ui/editor/controllers/text_editing_driver.dart, build, controller, EditorSurface, mode, _ModeBadge

### Community 69 - "Map"
Cohesion: 0.29
Nodes (6): Map, build, CardView, data, onDelete, onTap

### Community 70 - "MaterialPageRoute"
Cohesion: 0.29
Nodes (7): MaterialPageRoute, _createBubble, _openEngram, _openPlan, addBubbleWidget, addNote, _openNote

### Community 71 - "package:flutter/foundation.dart"
Cohesion: 0.29
Nodes (6): package:cerebrum/services/user_session.dart, package:cerebrum/ui/app_entry.dart, package:flutter/foundation.dart, build, DebugResetOnboardingButton, _reset

### Community 72 - "erase_split_test.dart"
Cohesion: 0.18
Nodes (9): package:cerebrum/main.dart, package:cerebrum/ui/editor/screens/drawing_layer.dart, package:flutter/painting.dart, package:flutter_test/flutter_test.dart, package:scribble/scribble.dart, _line, main, sketch (+1 more)

### Community 73 - "VoidCallback"
Cohesion: 0.29
Nodes (6): package:introduction_screen/introduction_screen.dart, build, OnboardingScreen, onDone, _page, VoidCallback

### Community 74 - "responsive_layout.dart"
Cohesion: 0.29
Nodes (6): build, desktop, mobileBreakpoint, ResponsiveLayout, static const int, Widget

### Community 75 - "EditorState"
Cohesion: 0.40
Nodes (6): BlockComponentStatefulWidget, EditorState, AiBlockComponentWidget, _AiBlockComponentWidgetState, CodeBlockComponentWidget, _CodeBlockComponentWidgetState

### Community 76 - "EngramAttempts"
Cohesion: 0.40
Nodes (5): @DataClassName, CachedEngrams, EngramAttempts, EngramMasteryRows, Table

### Community 77 - "BlockComponentBuilder"
Cohesion: 0.67
Nodes (3): BlockComponentBuilder, AiBlockComponentBuilder, CodeBlockComponentBuilder

### Community 111 - "Phase 0 Foundation"
Cohesion: 0.40
Nodes (5): Phase 0 Foundation, Phase 1 Core Feature, Phase 2 Features, Phase 3 Hardening, Phase 4 Ship

### Community 112 - "_DLearningCenterPageState"
Cohesion: 0.67
Nodes (3): SingleTickerProviderStateMixin, DLearningCenterPage, _DLearningCenterPageState

## Knowledge Gaps
- **1252 isolated node(s):** `ApiConfig`, `_keyMode`, `_keyLocalUrl`, `_keyCloudUrl`, `_defaultLocalUrl` (+1247 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **49 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `Engram` connect `engram_store.dart` to `engram_models.dart`, `long_questions.dart`, `mcq.dart`, `flashcard.dart`, `short_question.dart`?**
  _High betweenness centrality (0.012) - this node is a cross-community bridge._
- **Why does `_UpcomingEngramsSectionState` connect `State` to `upcoming_engrams.dart`?**
  _High betweenness centrality (0.007) - this node is a cross-community bridge._
- **Why does `EngramAttempt` connect `short_question.dart` to `long_questions.dart`, `mcq.dart`, `flashcard.dart`, `engram_attempt_store.dart`?**
  _High betweenness centrality (0.005) - this node is a cross-community bridge._
- **What connects `ApiConfig`, `_keyMode`, `_keyLocalUrl` to the rest of the system?**
  _1252 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Cross-Repo Contracts` be split into smaller, more focused modules?**
  _Cohesion score 0.0659536541889483 - nodes in this community are weakly interconnected._
- **Should `radial_tool_dial.dart` be split into smaller, more focused modules?**
  _Cohesion score 0.014705882352941176 - nodes in this community are weakly interconnected._
- **Should `app_database.dart` be split into smaller, more focused modules?**
  _Cohesion score 0.019417475728155338 - nodes in this community are weakly interconnected._