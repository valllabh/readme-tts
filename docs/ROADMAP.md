# Roadmap

Drawn from competitive research (Speechify, Voice Dream Reader,
NaturalReader, ElevenLabs Reader, GhostReader, macOS Spoken Content,
Pocket/Matter, Speak11, open source Piper/Kokoro readers). Guiding rules:
privacy first (no accounts, no meter, no cloud voices, nothing leaves the
Mac), performant, stable. Items marked [$] are features competitors
paywall that local generation makes free.

## Shipped

- Playback speed 0.5x to 3x, pitch preserved, live mid read [$]
  (Speechify paywalls above 1.5x)
- Export read audio to m4a or wav [$] (NaturalReader paywalls export,
  ElevenLabs forbids it)
- Sentence skip on hotkeys, media player back-restart semantics
- Sleep timer (15, 30, 60 minutes)
- Read Clipboard, no permissions needed
- HTML structure capture from browsers (headings pause, tables read as
  rows, images dropped)
- Live position display in the transport row

## Next, by value over effort

1. Reading queue with auto advance: stack captures, play through them,
   the orphaned Pocket listening model. Listening is hands free; next
   item continuity beats in-article controls.
2. Resume and position memory across launches: persist last text plus
   sample offset.
3. Floating mini player: small always on top panel with transport,
   speed, progress.
4. Sentence highlighting in a reader window (karaoke): sentence level
   falls out of chunk timing for free; the dyslexia and immersion use
   case that drives loyalty to Speechify and Voice Dream. Word level
   needs forced alignment, skip for now.
5. Pronunciation dictionary: user editable word to spoken form map
   feeding TextNormalizer [$] (ElevenLabs charges for this).
6. URL or article mode: paste a URL, extract the article locally
   (readability heuristics), queue it. Pairs with the queue as the
   Pocket replacement story.
7. macOS Shortcuts actions (Speak Text, Speak Clipboard, Export Audio):
   none of the big four ship first class Shortcuts support.
8. PDF and EPUB import with junk skipping (headers, footers, citations)
   [$] (Speechify monetizes this as Enhance Skipping). PDFKit text plus
   heuristics.
9. Personal podcast feed: serve finished audio as a local RSS feed that
   Apple Podcasts can subscribe to. Recurring power user wish nobody
   ships; CommandServer is a natural host.
10. More voices via additional MLX models (Kokoro under MLX has open,
    documented demand from the Audiblez community).

## Anti goals

- No accounts, no metering, no cloud voice option. The loudest
  complaints against every paid competitor are hidden caps, expiring
  credits, trial traps, and subscription pivots (Voice Dream 2024,
  ElevenLabs 2025). Local first is structurally immune; keep it so.
- No extreme speed claims (Speechify's 5x is a documented credibility
  wound).

Positioning line the research supports: every paid competitor's top
complaint is the meter, not the voice. "No meter, no account, nothing
leaves your Mac."
